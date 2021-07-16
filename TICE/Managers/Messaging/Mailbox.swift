//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//

import Foundation
import TICEAPIModels
import ConvAPI
import PromiseKit
import Sodium

public enum MailboxError: LocalizedError {
    case membershipCertificateMissing

    public var errorDescription: String? {
        switch self {
        case .membershipCertificateMissing: return "Membership certificate missing."
        }
    }
}

class Mailbox: MailboxType {

    private let backend: TICEAPI
    private let signedInUser: SignedInUser
    private let cryptoManager: CryptoManagerType
    private var conversationManager: ConversationManagerType
    private let encoder: JSONEncoder

    struct EncryptionResult {
        let ciphertext: Ciphertext
        let messageKey: SecretKey
    }

    init(backend: TICEAPI, signedInUser: SignedInUser, cryptoManager: CryptoManagerType, conversationManager: ConversationManagerType, encoder: JSONEncoder) {
        self.backend = backend
        self.signedInUser = signedInUser
        self.cryptoManager = cryptoManager
        self.conversationManager = conversationManager
        self.encoder = encoder

        self.conversationManager.delegate = self
    }

    deinit {
        self.conversationManager.delegate = nil
    }

    func send(payloadContainer: PayloadContainer, to members: [Membership], serverSignedMembershipCertificate: Certificate, priority: MessagePriority, collapseId: Envelope.CollapseIdentifier?) -> Promise<Void> {
        logger.debug("Sending message of type \(payloadContainer.payloadType) to \(members.count) recipients.")

        return firstly { () -> Promise<Void> in
            let encryptedPayloadContainer = try encrypt(payloadContainer: payloadContainer)

            return firstly { () -> Guarantee<[Result<Recipient>]> in
                let recipientPromises = members.map { member -> Promise<Recipient> in
                    return recipient(userId: member.userId, serverSignedMembershipCertificate: member.serverSignedMembershipCertificate, messageKey: encryptedPayloadContainer.messageKey, collapsing: collapseId != nil)
                }

                return when(resolved: recipientPromises)
            }.then { recipientResults -> Promise<([UserId], [Promise<Void>])> in
                var recipients: Set<Recipient> = Set()
                var retries: [Promise<Void>] = []
                var retryRecipients: [UserId] = []
                for (recipient, result) in zip(members, recipientResults) {
                    switch result {
                    case .fulfilled(let recipient):
                        recipients.insert(recipient)
                    case .rejected(let error):
                        logger.error("Could not send message to recipient \(recipient.userId.uuidString): \(String(describing: error))")
                        logger.debug("Try sending message again and resync conversation.")

                        let retry = firstly {
                            self.conversationManager.initConversation(userId: recipient.userId, collapsing: collapseId != nil)
                        }.then {
                            self.send(payloadContainer: payloadContainer, to: recipient.userId, receiverServerSignedMembershipCertificate: recipient.serverSignedMembershipCertificate, senderServerSignedMembershipCertificate: serverSignedMembershipCertificate, collapseId: collapseId)
                        }
                        retries.append(retry)
                        retryRecipients.append(recipient.userId)
                    }
                }

                guard !recipients.isEmpty else {
                    logger.info("Not sending message because set of recipients is empty.")
                    return .value((retryRecipients, retries))
                }

                return self.post(encryptedMessage: encryptedPayloadContainer.ciphertext,
                                 serverSignedMembershipCertificate: serverSignedMembershipCertificate,
                                 senderId: self.signedInUser.userId,
                                 recipients: recipients,
                                 priority: priority,
                                 collapseId: collapseId).map { (retryRecipients, retries) }
            }.then { retryRecipients, retries -> Promise<Void> in
                guard !retries.isEmpty else {
                    return .value(())
                }

                return firstly {
                    when(resolved: retries)
                }.done { results in
                    for (recipient, result) in zip(retryRecipients, results) {
                        if case .rejected(let error) = result {
                            logger.error("Retry sending message to \(recipient): \(String(describing: error)).")
                        }
                    }
                }
            }
        }
    }

    private func send(payloadContainer: PayloadContainer?, to userId: UserId, receiverServerSignedMembershipCertificate: Certificate, senderServerSignedMembershipCertificate: Certificate, collapseId: Envelope.CollapseIdentifier?) -> Promise<Void> {
        let payloadContainer = payloadContainer ?? PayloadContainer(payloadType: .resetConversationV1, payload: ResetConversation())

        return firstly { () -> Promise<Void> in
            let encryptedPayloadContainer = try encrypt(payloadContainer: payloadContainer)
            return firstly {
                self.recipient(userId: userId, serverSignedMembershipCertificate: receiverServerSignedMembershipCertificate, messageKey: encryptedPayloadContainer.messageKey, collapsing: collapseId != nil)
            }.then { recipient in
                return self.post(encryptedMessage: encryptedPayloadContainer.ciphertext,
                                 serverSignedMembershipCertificate: senderServerSignedMembershipCertificate,
                                 senderId: self.signedInUser.userId,
                                 recipients: [recipient],
                                 priority: .background,
                                 collapseId: collapseId)
            }
        }
    }

    private func post(encryptedMessage: Data, serverSignedMembershipCertificate: Certificate, senderId: UserId, recipients: Set<Recipient>, priority: MessagePriority, collapseId: Envelope.CollapseIdentifier? = nil, messageTimeToLive: TimeInterval? = nil) -> Promise<Void> {
        let id = MessageId()
        let timestamp = Date()

        return backend.message(id: id,
                               senderId: senderId,
                               timestamp: timestamp,
                               encryptedMessage: encryptedMessage,
                               serverSignedMembershipCertificate: serverSignedMembershipCertificate,
                               recipients: recipients,
                               priority: priority,
                               collapseId: collapseId)
    }

    private func recipient(userId: UserId, serverSignedMembershipCertificate: Certificate, messageKey: SecretKey, collapsing: Bool) -> Promise<Recipient> {
        return firstly {
            conversationManager.encrypt(data: Data(messageKey), for: userId, collapsing: collapsing)
        }.map { encryptedMessageKey in
            let conversationInvitation = self.conversationManager.conversationInvitation(userId: userId, collapsing: collapsing)
            return Recipient(userId: userId, serverSignedMembershipCertificate: serverSignedMembershipCertificate, encryptedMessageKey: encryptedMessageKey, conversationInvitation: conversationInvitation)
        }
    }

    private func encrypt(payloadContainer: PayloadContainer) throws -> EncryptionResult {
        let serializedPayloadContainer = try encoder.encode(payloadContainer)
        let (ciphertext, messageKey) = try cryptoManager.encrypt(serializedPayloadContainer)
        return EncryptionResult(ciphertext: ciphertext, messageKey: messageKey)
    }
}

extension Mailbox: ConversationManagerDelegate {
    func sendResetReply(to userId: UserId, receiverCertificate: Certificate, senderCertificate: Certificate, collapseId: Envelope.CollapseIdentifier?) -> Promise<Void> {
        send(payloadContainer: nil, to: userId, receiverServerSignedMembershipCertificate: receiverCertificate, senderServerSignedMembershipCertificate: senderCertificate, collapseId: collapseId)
    }
}
