//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels

protocol ConversationCryptoMiddlewareType {
    func renewHandshakeKeyMaterial(privateSigningKey: PrivateKey) throws -> UserPublicKeys
    func initConversation(with userId: UserId, conversationId: ConversationId, remoteIdentityKey: PublicKey, remoteSignedPrekey: PublicKey, remotePrekeySignature: Signature, remoteOneTimePrekey: PublicKey?, remoteSigningKey: PublicKey) throws -> ConversationInvitation
    func processConversationInvitation(_ conversationInvitation: ConversationInvitation, from userId: UserId, conversationId: ConversationId) throws
    func conversationExisting(userId: UserId, conversationId: ConversationId) -> Bool

    func conversationFingerprint(ciphertext: Ciphertext) throws -> ConversationFingerprint

    func encrypt(_ data: Data, for userId: UserId, conversationId: ConversationId) throws -> Ciphertext
    func decrypt(encryptedData: Data, encryptedSecretKey: Data, from userId: UserId, conversationId: ConversationId) throws -> Data
}
