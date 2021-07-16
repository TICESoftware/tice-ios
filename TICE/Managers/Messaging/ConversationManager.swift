//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels
import PromiseKit
import DoubleRatchet

enum ConversationManagerError: LocalizedError {
    case invalidConversation
    case obsoleteMessage
    case conversationHasBeenResynced
    case certificateMissing
    case mailboxMissing
    case noDelegate

    var errorDescription: String? {
        switch self {
        case .invalidConversation: return "This conversation has been invalidated before."
        case .obsoleteMessage: return "This message is obsolete and has been discarded."
        case .conversationHasBeenResynced: return "This conversation needs to be resynced."
        case .certificateMissing: return "A required certificate is missing."
        case .mailboxMissing: return "No mailbox accessible."
        case .noDelegate: return "No delegate set."
        }
    }
}

class ConversationManager: ConversationManagerType {
    let cryptoManager: CryptoManagerType
    let conversationCryptoMiddleware: ConversationCryptoMiddlewareType
    let storageManager: ConversationStorageManagerType
    weak var postOffice: PostOfficeType?
    let backend: TICEAPI
    let decoder: JSONDecoder
    let tracker: TrackerType
    let collapsingConversationIdentifier: ConversationId
    let nonCollapsingConversationIdentifier: ConversationId
    let resendResetTimeout: TimeInterval

    weak var delegate: ConversationManagerDelegate?

    @SynchronizedProperty var userQueues: [UserId: DispatchQueue] = [:]
    
    @SynchronizedProperty var lastResets: [Conversation: Date] = [:]

    init(cryptoManager: CryptoManagerType, conversationCryptoMiddleware: ConversationCryptoMiddlewareType, storageManager: ConversationStorageManagerType, postOffice: PostOfficeType, backend: TICEAPI, decoder: JSONDecoder, tracker: TrackerType, collapsingConversationIdentifier: ConversationId, nonCollapsingConversationIdentifier: ConversationId, resendResetTimeout: TimeInterval) {
        self.cryptoManager = cryptoManager
        self.conversationCryptoMiddleware = conversationCryptoMiddleware
        self.storageManager = storageManager
        self.postOffice = postOffice
        self.backend = backend
        self.decoder = decoder
        self.tracker = tracker
        self.collapsingConversationIdentifier = collapsingConversationIdentifier
        self.nonCollapsingConversationIdentifier = nonCollapsingConversationIdentifier
        self.resendResetTimeout = resendResetTimeout
    }

    deinit {
        self.postOffice?.decodingStrategies[.encryptedPayloadContainerV1] = nil
        self.postOffice?.handlers[.resetConversationV1] = nil
    }

    func registerHandler() {
        guard self.postOffice?.decodingStrategies[.encryptedPayloadContainerV1] == nil else {
            logger.debug("Decoding strategy for encrypted group messages already registered.")
            return
        }

        self.postOffice?.decodingStrategies[.encryptedPayloadContainerV1] = decrypt(payload:metaInfo:)
        self.postOffice?.handlers[.resetConversationV1] = handleConversationResync(payload:metaInfo:completion:)
    }

    private func conversationId(collapsing: Bool) -> ConversationId {
        return collapsing ? collapsingConversationIdentifier : nonCollapsingConversationIdentifier
    }

    func initConversation(userId: UserId, collapsing: Bool) -> Promise<Void> {
        return firstly { () -> Promise<GetUserPublicKeysResponse> in
            self.backend.getUserKeys(userId: userId)
        }.done(on: userQueue(userId: userId)) { getUserKeysResponse in
            let conversationId = self.conversationId(collapsing: collapsing)
            let conversationInvitation = try self.conversationCryptoMiddleware.initConversation(with: userId, conversationId: conversationId, remoteIdentityKey: getUserKeysResponse.identityKey, remoteSignedPrekey: getUserKeysResponse.signedPrekey, remotePrekeySignature: getUserKeysResponse.prekeySignature, remoteOneTimePrekey: getUserKeysResponse.oneTimePrekey, remoteSigningKey: getUserKeysResponse.signingKey)
            try self.storageManager.storeOutboundConversationInvitation(receiverId: userId, conversationId: conversationId, conversationInvitation: conversationInvitation)
            logger.debug("Created new conversation invitation for user \(userId)\(collapsing ? " (collapsing)": ""). Used one-time prekey: \(conversationInvitation.usedOneTimePrekey?.hexEncodedString() ?? "n/a")")
        }
    }

    func isConversationInitialized(userId: UserId, collapsing: Bool) -> Bool {
        conversationCryptoMiddleware.conversationExisting(userId: userId, conversationId: conversationId(collapsing: collapsing))
    }

    func conversationInvitation(userId: UserId, collapsing: Bool) -> ConversationInvitation? {
        do {
            return try storageManager.outboundConversationInvitation(receiverId: userId, conversationId: conversationId(collapsing: collapsing))
        } catch {
            logger.error("Could not load outbound conversation invitation: \(String(describing: error))")
            return nil
        }
    }

    func encrypt(data: Data, for userId: UserId, collapsing: Bool) -> Promise<Ciphertext> {
        return firstly { () -> Promise<Void> in
            !isConversationInitialized(userId: userId, collapsing: collapsing) ? self.initConversation(userId: userId, collapsing: collapsing) : .value(())
        }.map(on: userQueue(userId: userId)) {
            try self.conversationCryptoMiddleware.encrypt(data, for: userId, conversationId: self.conversationId(collapsing: collapsing))
        }
    }

    func decrypt(payload: Payload, metaInfo: PayloadMetaInfo) throws -> PayloadContainerBundle {
        guard let encryptedPayloadContainer = payload as? EncryptedPayloadContainer else {
            logger.error("Invalid payload type. Expected encrypted payload container.")
            throw PostOfficeError.invalidPayloadType
        }

        return try userQueue(userId: metaInfo.senderId).sync { try decrypt(encryptedPayloadContainer, metaInfo: metaInfo) }
    }

    private func decrypt(_ encryptedPayloadContainer: EncryptedPayloadContainer, metaInfo: PayloadMetaInfo) throws -> PayloadContainerBundle {
        let conversationId = self.conversationId(collapsing: metaInfo.collapseId != nil)
        let conversationFingerprint = try conversationCryptoMiddleware.conversationFingerprint(ciphertext: encryptedPayloadContainer.encryptedKey)
        let ciphertextFingerprint = String(encryptedPayloadContainer.ciphertext.hexEncodedString().prefix(8))
        
        if let lastReset = try storageManager.receivedReset(senderId: metaInfo.senderId, conversationId: conversationId),
            metaInfo.timestamp < lastReset {
            logger.debug("Discard message because it is older than the last reset received from the sender.")
            throw ConversationManagerError.invalidConversation
        }
        
        if let conversationInvitation = metaInfo.conversationInvitation {
            var processConversationInvitation = false
            if let lastInvitation = try storageManager.inboundConversationInvitation(senderId: metaInfo.senderId, conversationId: conversationId) {
                if lastInvitation.conversationInvitation != conversationInvitation && metaInfo.timestamp > lastInvitation.timestamp {
                    logger.debug("The attached conversation invitation is newer than the last we encountered in conversation with \(metaInfo.senderId)\(metaInfo.collapseId != nil ? " (collapsing)": ""). Ciphertext: \(ciphertextFingerprint). Used one-time prekey: \(conversationInvitation.usedOneTimePrekey?.hexEncodedString() ?? "n/a")")
                    processConversationInvitation = true
                } else {
                    logger.debug("Discard conversation invitation because it equals the last one or is older than the last one. Conversation with \(metaInfo.senderId)\(metaInfo.collapseId != nil ? " (collapsing)": ""). Ciphertext: \(ciphertextFingerprint). Used one-time prekey: \(conversationInvitation.usedOneTimePrekey?.hexEncodedString() ?? "n/a")")
                }
            } else {
                logger.debug("This is the first invitation in conversation with \(metaInfo.senderId)\(metaInfo.collapseId != nil ? " (collapsing)": ""). Ciphertext: \(ciphertextFingerprint). Used one-time prekey: \(conversationInvitation.usedOneTimePrekey?.hexEncodedString() ?? "n/a")")
                processConversationInvitation = true
            }

            if processConversationInvitation {
                logger.debug("Using conversation invitation to initialize conversation with user \(metaInfo.senderId)\(metaInfo.collapseId != nil ? " (collapsing)": ""). Ciphertext: \(ciphertextFingerprint). Used one-time prekey: \(conversationInvitation.usedOneTimePrekey?.hexEncodedString() ?? "n/a")")
                do {
                    try conversationCryptoMiddleware.processConversationInvitation(conversationInvitation, from: metaInfo.senderId, conversationId: conversationId)
                } catch {
                    logger.error("Error during conversation invitation processing: \(String(describing: error)). Resync conversation. Ciphertext: \(ciphertextFingerprint). Conversation fingerprint: \(conversationFingerprint)")

                    if case CryptoStorageManagerError.invalidOneTimePrekey = error {
                        tracker.log(action: .error, category: .conversation, detail: "invalidOneTimePrekey")
                    }

                    let fingerprint = try conversationCryptoMiddleware.conversationFingerprint(ciphertext: encryptedPayloadContainer.encryptedKey)
                    resyncConversationAsynchronously(fingerprint: fingerprint, metaInfo: metaInfo)
                    
                    throw ConversationManagerError.conversationHasBeenResynced
                }
                try storageManager.storeInboundConversationInvitation(senderId: metaInfo.senderId, conversationId: conversationId, conversationInvitation: conversationInvitation, timestamp: metaInfo.timestamp)
            }
        }

        guard isConversationInitialized(userId: metaInfo.senderId, collapsing: metaInfo.collapseId != nil) else {
            throw ConversationManagerError.invalidConversation
        }

        if let lastInvalidConversation = try storageManager.invalidConversation(userId: metaInfo.senderId, conversationId: conversationId) {
            if lastInvalidConversation.conversationFingerprint == conversationFingerprint {
                if metaInfo.timestamp > lastInvalidConversation.resendResetTimeout {
                    logger.debug("Message from invalid conversation received that is older than a minute after the last sent reset. Resend reset. Conversation fingerprint: \(conversationFingerprint)")
                    try storageManager.updateInvalidConversation(userId: metaInfo.senderId, conversationId: conversationId, resendResetTimeout: Date().addingTimeInterval(resendResetTimeout))
                    replyWithReset(metaInfo: metaInfo).catch {
                        self.tracker.log(action: .error, category: .conversation, detail: "replyWithResetFailed")
                        logger.error("Sending reset message failed: \(String(describing: $0))")
                    }
                }
                throw ConversationManagerError.invalidConversation
            }

            if lastInvalidConversation.timestamp > metaInfo.timestamp {
                throw ConversationManagerError.invalidConversation
            }
        }

        do {
            let plaintext = try conversationCryptoMiddleware.decrypt(encryptedData: encryptedPayloadContainer.ciphertext, encryptedSecretKey: encryptedPayloadContainer.encryptedKey, from: metaInfo.senderId, conversationId: conversationId)
            try storageManager.deleteOutboundConversationInvitation(receiverId: metaInfo.senderId, conversationId: conversationId)

            let payloadContainer = try decoder.decode(PayloadContainer.self, from: plaintext)
            var metaInfo = metaInfo
            metaInfo.authenticated = true

            return PayloadContainerBundle(payloadContainer: payloadContainer, metaInfo: metaInfo)
        } catch {
            switch error {
            case ConversationCryptoMiddlewareError.decryptionError:
                tracker.log(action: .error, category: .conversation, detail: "decryptionError")
                logger.error("Failed to decrypt message. Sender: \(metaInfo.senderId)\(metaInfo.collapseId != nil ? " (collapsing)": ""). Ciphertext: \(ciphertextFingerprint).")
            case ConversationCryptoMiddlewareError.maxSkipExceeded:
                tracker.log(action: .error, category: .conversation, detail: "maxSkipExceeded")
                logger.error("Skipped more then maxSkip messages. Sender: \(metaInfo.senderId)\(metaInfo.collapseId != nil ? " (collapsing)": ""). Ciphertext: \(ciphertextFingerprint).")
            case ConversationCryptoMiddlewareError.discardedObsoleteMessage:
                logger.debug("Discarded obsolete message.")
                throw ConversationManagerError.obsoleteMessage
            default:
                throw error
            }

            resyncConversationAsynchronously(fingerprint: conversationFingerprint, metaInfo: metaInfo)
            
            throw ConversationManagerError.conversationHasBeenResynced
        }
    }

    private func replyWithReset(metaInfo: PayloadMetaInfo) -> Promise<Void> {
        return firstly { () -> Promise<Void> in
            guard let receiverCertificate = metaInfo.senderServerSignedMembershipCertificate,
                let senderCertificate = metaInfo.receiverServerSignedMembershipCertificate else {
                    throw ConversationManagerError.certificateMissing
            }

            guard let delegate = delegate else {
                throw ConversationManagerError.noDelegate
            }

            let collapseId = metaInfo.collapseId
            return delegate.sendResetReply(to: metaInfo.senderId, receiverCertificate: receiverCertificate, senderCertificate: senderCertificate, collapseId: collapseId)
        }
    }

    private func userQueue(userId: UserId) -> DispatchQueue {
        if let queue = userQueues[userId] {
            return queue
        } else {
            let queue = DispatchQueue(label: "app.tice.TICE.GroupMessageDecryptor.\(userId.uuidString)")
            userQueues[userId] = queue
            return queue
        }
    }

    private func resyncConversationAsynchronously(fingerprint: ConversationFingerprint, metaInfo: PayloadMetaInfo) {
        logger.debug("Invalidating conversation with fingerprint: \(fingerprint).")

        let conversationId = self.conversationId(collapsing: metaInfo.collapseId != nil)
        let conversation = Conversation(userId: metaInfo.senderId, conversationId: conversationId)
        
        if let lastReset = lastResets[conversation],
            lastReset.addingTimeInterval(resendResetTimeout) > Date() {
            logger.debug("Don't resync conversation because the conversation has been resynced recently.")
            return
        }
        self.lastResets[conversation] = Date()
        
        firstly { () -> Promise<Void> in
            try storageManager.storeInvalidConversation(userId: metaInfo.senderId, conversationId: conversationId, fingerprint: fingerprint, timestamp: metaInfo.timestamp, resendResetTimeout: Date())
            return initConversation(userId: metaInfo.senderId, collapsing: metaInfo.collapseId != nil)
        }.then {
            self.replyWithReset(metaInfo: metaInfo)
        }.catch { error in
            self.tracker.log(action: .error, category: .conversation, detail: "resyncFailed")
            logger.error("Failed to resync conversation: \(error)")
        }
    }

    func handleConversationResync(payload: Payload, metaInfo: PayloadMetaInfo, completion: PostOfficeType.PayloadHandler?) {
        guard payload is ResetConversation else {
            logger.error("Invalid payload type. Expected reset conversation.")
            completion?(.failed)
            return
        }
        
        let conversationId = self.conversationId(collapsing: metaInfo.collapseId != nil)
        do {
            try storageManager.storeReceivedReset(senderId: metaInfo.senderId, conversationId: conversationId, timestamp: metaInfo.timestamp)
        } catch {
            tracker.log(action: .error, category: .conversation, detail: "persistingResyncFailed")
            logger.error("Could not persist received reset: \(error)")
        }
        
        completion?(.noData)
    }
}
