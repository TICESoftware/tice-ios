//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import DoubleRatchet
import Sodium

class DoubleRatchetProvider: DoubleRatchetProviderType {
    func provideDoubleRatchet(
        keyPair: KeyExchange.KeyPair?,
        remotePublicKey: KeyExchange.PublicKey?,
        sharedSecret: Bytes,
        maxSkip: Int,
        info: String,
        messageKeyCache: MessageKeyCache?
    ) throws -> DoubleRatchetType {
        try DoubleRatchet(
            keyPair: keyPair,
            remotePublicKey: remotePublicKey,
            sharedSecret: sharedSecret,
            maxSkip: maxSkip,
            info: info,
            messageKeyCache: messageKeyCache
        )
    }
    
    func provideDoubleRatchet(sessionState: SessionState, messageKeyCache: MessageKeyCache?) -> DoubleRatchetType {
        DoubleRatchet(sessionState: sessionState, messageKeyCache: messageKeyCache)
    }
}
