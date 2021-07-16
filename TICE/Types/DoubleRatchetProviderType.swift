//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import Sodium
import DoubleRatchet

protocol DoubleRatchetProviderType {
    func provideDoubleRatchet(keyPair: KeyExchange.KeyPair?, remotePublicKey: KeyExchange.PublicKey?, sharedSecret: Bytes, maxSkip: Int, info: String, messageKeyCache: MessageKeyCache?) throws -> DoubleRatchetType
    func provideDoubleRatchet(sessionState: SessionState, messageKeyCache: MessageKeyCache?) -> DoubleRatchetType
}
