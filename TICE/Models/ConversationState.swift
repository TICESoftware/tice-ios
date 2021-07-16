//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation

struct ConversationState: Codable, Equatable {
    let userId: UserId
    let conversationId: ConversationId

    let rootKey: SecretKey
    let rootChainPublicKey: PublicKey
    let rootChainPrivateKey: PrivateKey
    var rootChainKeyPair: KeyPair { KeyPair(privateKey: rootChainPrivateKey, publicKey: rootChainPublicKey) }
    let rootChainRemotePublicKey: PublicKey?
    let sendingChainKey: SecretKey?
    let receivingChainKey: SecretKey?

    let sendMessageNumber: Int
    let receivedMessageNumber: Int
    let previousSendingChainLength: Int
}
