//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import protocol DoubleRatchet.MessageKeyCache

protocol CryptoStorageManagerType: DeletableStorageManagerType {
    func saveIdentityKeyPair(_ keyPair: KeyPair) throws
    func loadIdentityKeyPair() throws -> KeyPair
    func savePrekeyPair(_ keyPair: KeyPair, signature: Signature) throws
    func loadPrekeyPair() throws -> KeyPair
    func loadPrekeySignature() throws -> Signature
    func saveOneTimePrekeyPairs(_ keyPairs: [KeyPair]) throws
    func loadPrivateOneTimePrekey(publicKey: PublicKey) throws -> PrivateKey
    func deleteOneTimePrekeyPair(publicKey: PublicKey) throws
    
    func save(_ conversationState: ConversationState) throws
    func loadConversationState(userId: UserId, conversationId: ConversationId) throws -> ConversationState?
    func messageKeyCache(conversationId: ConversationId) throws -> MessageKeyCache
}
