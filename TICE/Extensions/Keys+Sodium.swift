//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import Sodium

extension KeyExchange.PublicKey {
    var dataKey: PublicKey { Data(self) }
}

extension KeyExchange.KeyPair {
    var dataKeyPair: KeyPair {
        KeyPair(privateKey: Data(secretKey), publicKey: publicKey.dataKey)
    }
}

extension PublicKey {
    var keyExchangeKey: KeyExchange.PublicKey { Bytes(self) }
}

extension KeyPair {
    var keyExchangeKeyPair: KeyExchange.KeyPair {
        KeyExchange.KeyPair(publicKey: publicKey.keyExchangeKey, secretKey: Bytes(privateKey))
    }
}
