//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels
import PromiseKit

enum PostOfficeError: LocalizedError {
    case invalidPayloadType
    case duplicate

    var errorDescription: String? {
        switch self {
        case .invalidPayloadType: return "PostOfficeError_invalidPayloadType"
        case .duplicate: return "PostOfficeError_duplicate"
        }
    }
}

public struct PayloadMetaInfo {
    
    let envelopeId: MessageId
    let senderId: UserId
    let timestamp: Date
    let collapseId: Envelope.CollapseIdentifier?
    let senderServerSignedMembershipCertificate: Certificate?
    let receiverServerSignedMembershipCertificate: Certificate?
    var authenticated: Bool = false
    let conversationInvitation: ConversationInvitation?

    init(envelopeId: MessageId, senderId: UserId, timestamp: Date, collapseId: Envelope.CollapseIdentifier?, senderServerSignedMembershipCertificate: Certificate?, receiverServerSignedMembershipCertificate: Certificate?, conversationInvitation: ConversationInvitation?) {
        self.envelopeId = envelopeId
        self.senderId = senderId
        self.timestamp = timestamp
        self.collapseId = collapseId
        self.senderServerSignedMembershipCertificate = senderServerSignedMembershipCertificate
        self.receiverServerSignedMembershipCertificate = receiverServerSignedMembershipCertificate
        self.conversationInvitation = conversationInvitation
    }
}

public struct PayloadContainerBundle {
    let payloadContainer: PayloadContainer
    let metaInfo: PayloadMetaInfo
}

public class PostOffice: PostOfficeType, EnvelopeReceiverDelegate {

    let storageManager: PostOfficeStorageManagerType
    let backend: TICEAPI

    private let queue = DispatchQueue(label: "app.tice.TICE.PostOffice.queue")
    
    @SynchronizedProperty var handlers: [PayloadContainer.PayloadType: Handler] = [:]
    @SynchronizedProperty var decodingStrategies: [PayloadContainer.PayloadType: DecodingStrategy] = [:]
    @SynchronizedProperty var decodingSuccessInterceptor: ((PayloadContainerBundle) -> Void)?

    public let envelopeCacheTime: TimeInterval
    private var lastTimeCacheCleaned: Date?
    
    init(storageManager: PostOfficeStorageManagerType, backend: TICEAPI, envelopeCacheTime: TimeInterval) {
        self.storageManager = storageManager
        self.backend = backend
        self.envelopeCacheTime = envelopeCacheTime
    }

    func fetchMessages() -> Promise<Void> {
        queue.async(.promise) {
            let getMessagesResponse = try self.backend.getMessages().wait()
            self.receiveSync(envelopeBatch: getMessagesResponse.messages)
        }
    }
        
    func receive(envelope: Envelope) {
        queue.async {
            self.receiveSync(envelope: envelope, timeout: nil, completionHandler: nil)
        }
    }

    private func receiveSync(envelopeBatch: [Envelope]) {
        // Sort by collapseId
        var collapsedPayloadContainers: [Envelope.CollapseIdentifier: PayloadContainerBundle] = [:]
        logger.debug("Receiving \(envelopeBatch.count) batched envelopes")
        
        for envelope in envelopeBatch {
            let unpackedEnvelope: PayloadContainerBundle
            do {
                logger.debug("[Envelope \(envelope.id)] Completed with result")
                unpackedEnvelope = try self.unpack(envelope: envelope)
            } catch {
                logger.error("[Envelope \(envelope.id)] Could not decode payload container. \(error.localizedDescription)")
                self.storageManager.updateCacheRecord(for: envelope, state: .handled)
                continue
            }

            if let collapseId = envelope.collapseId {
                guard let previousPayloadContainerBundle = collapsedPayloadContainers[collapseId] else {
                    logger.debug("[Envelope \(envelope.id)] Container bundle incorrect. Skipping.")
                    collapsedPayloadContainers[collapseId] = unpackedEnvelope
                    continue
                }

                logger.debug("[Envelope \(envelope.id)] Discard payload container due to collapsing.")
                if previousPayloadContainerBundle.metaInfo.timestamp < unpackedEnvelope.metaInfo.timestamp {
                    collapsedPayloadContainers[collapseId] = unpackedEnvelope
                }
            } else {
                logger.debug("[Envelope \(envelope.id)] Handling payload container")
                self.handle(payloadContainer: unpackedEnvelope.payloadContainer, metaInfo: unpackedEnvelope.metaInfo, timeout: nil, completionHandler: nil)
            }
        }

        logger.debug("Handling collapsed payload containers")
        for payloadContainerBundle in collapsedPayloadContainers.values {
            self.handle(payloadContainer: payloadContainerBundle.payloadContainer, metaInfo: payloadContainerBundle.metaInfo, timeout: nil, completionHandler: nil)
        }
    }
    
    func receive(envelope: Envelope, timeout: TimeInterval?, completionHandler: ((ReceiveEnvelopeResult) -> Void)?) {
        queue.async {
            self.receiveSync(envelope: envelope, timeout: timeout, completionHandler: completionHandler)
        }
    }
    
    private func receiveSync(envelope: Envelope, timeout: TimeInterval?, completionHandler: ((ReceiveEnvelopeResult) -> Void)?) {
        
        logger.debug("[Envelope \(envelope.id)] Checking for cache cleaning.")
        if let lastTimeCacheCleaned = lastTimeCacheCleaned {
            if lastTimeCacheCleaned.addingTimeInterval(envelopeCacheTime / 2.0) < Date() {
                cleanCache()
            }
        } else {
            cleanCache()
        }

        guard !storageManager.isCached(envelope: envelope) else {
            logger.debug("[Envelope \(envelope.id)] Envelope \(envelope.id) was already cached. Skipping duplicate handling.")
            completionHandler?(.duplicate)
            return
        }

        logger.debug("[Envelope \(envelope.id)] Updating cache for envelope.")
        self.storageManager.updateCacheRecord(for: envelope, state: .seen)
        let metaInfo = PayloadMetaInfo(envelopeId: envelope.id, senderId: envelope.senderId, timestamp: envelope.timestamp, collapseId: envelope.collapseId, senderServerSignedMembershipCertificate: envelope.senderServerSignedMembershipCertificate, receiverServerSignedMembershipCertificate: envelope.receiverServerSignedMembershipCertificate, conversationInvitation: envelope.conversationInvitation)
        
        do {
            let decodedPayloadContainer = try decode(payloadContainer: envelope.payloadContainer, metaInfo: metaInfo)
            self.storageManager.updateCacheRecord(for: envelope, state: .handled)
            decodingSuccessInterceptor?(decodedPayloadContainer)
            logger.debug("[Envelope \(envelope.id)] Handling ")
            handle(payloadContainer: decodedPayloadContainer.payloadContainer, metaInfo: decodedPayloadContainer.metaInfo, timeout: timeout, completionHandler: completionHandler)
        } catch {
            logger.error("[Envelope \(envelope.id)] Could not decode payload container. \(error.localizedDescription)")
            self.storageManager.updateCacheRecord(for: envelope, state: .handled)
            completionHandler?(.failed)
        }
    }

    private func unpack(envelope: Envelope) throws -> PayloadContainerBundle {
        guard !storageManager.isCached(envelope: envelope) else {
            throw PostOfficeError.duplicate
        }
        self.storageManager.updateCacheRecord(for: envelope, state: .seen)

        let metaInfo = PayloadMetaInfo(envelopeId: envelope.id, senderId: envelope.senderId, timestamp: envelope.timestamp, collapseId: envelope.collapseId, senderServerSignedMembershipCertificate: envelope.senderServerSignedMembershipCertificate, receiverServerSignedMembershipCertificate: envelope.receiverServerSignedMembershipCertificate, conversationInvitation: envelope.conversationInvitation)

        return try decode(payloadContainer: envelope.payloadContainer, metaInfo: metaInfo)
    }
    
    func handle(payloadContainer: PayloadContainer, metaInfo: PayloadMetaInfo, timeout: TimeInterval?, completionHandler: ((ReceiveEnvelopeResult) -> Void)?) {
        
        guard let handler = handlers[payloadContainer.payloadType] else {
            logger.warning("Received envelope \(metaInfo.envelopeId) with payload container of type \(payloadContainer.payloadType), but no handler is registered.")
            completionHandler?(.noData)
            return
        }
        
        logger.debug("Calling handler for envelope \(metaInfo.envelopeId) with \(payloadContainer.payloadType) \(completionHandler != nil ? "with" : "without") completion")
        
        var didCallCompletion = false
        let dispatchGroup = DispatchGroup()
        dispatchGroup.enter()
        handler(payloadContainer.payload, metaInfo, { result in
            guard !didCallCompletion else { return }
            didCallCompletion = true
            logger.debug("Completed processing envelope \(metaInfo.envelopeId) with payload container of type \(payloadContainer.payloadType) with some result.")
            completionHandler?(result)
            dispatchGroup.leave()
        })
        
        let waitTimeout = timeout ?? 10.000
        let waitResult = dispatchGroup.wait(wallTimeout: .now() + waitTimeout)
        if case .timedOut = waitResult {
            didCallCompletion = true
            logger.warning("Processing envelope \(metaInfo.envelopeId) with payload container of type \(payloadContainer.payloadType) timed out (\(waitTimeout)s). This should not happen.")
            completionHandler?(.timeOut)
        }
    }

    private func cleanCache() {
        logger.debug("Cleaning cache")
        do {
            try storageManager.deleteCacheRecordsOlderThan(Date().addingTimeInterval(-1.0 * envelopeCacheTime))
        } catch {
            logger.error("Failed to clean post office cache: \(String(describing: error))")
        }

        lastTimeCacheCleaned = Date()
    }
    
    private func decode(payloadContainer: PayloadContainer, metaInfo: PayloadMetaInfo) throws -> PayloadContainerBundle {
        guard let decodeStrategy = decodingStrategies[payloadContainer.payloadType] else {
            return PayloadContainerBundle(payloadContainer: payloadContainer, metaInfo: metaInfo)
        }

        let decodedPayloadContainer = try decodeStrategy(payloadContainer.payload, metaInfo)
        logger.debug("Decoded envelope \(metaInfo.envelopeId) with payload container of type \(decodedPayloadContainer.payloadContainer.payloadType) from \(decodedPayloadContainer.metaInfo.senderId)\(decodedPayloadContainer.metaInfo.conversationInvitation != nil ? " with conversation invitation" : "").")
        
        return try decode(payloadContainer: decodedPayloadContainer.payloadContainer, metaInfo: decodedPayloadContainer.metaInfo)
    }
}
