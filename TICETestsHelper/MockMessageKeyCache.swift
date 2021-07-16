//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import DoubleRatchet
import Sodium

struct MockMessageKeyCache: MessageKeyCache, Equatable {
    func add(messageKey: MessageKey, messageNumber: Int, publicKey: KeyExchange.PublicKey) throws { fatalError() }
    func getMessageKey(messageNumber: Int, publicKey: KeyExchange.PublicKey) throws -> MessageKey? { fatalError() }
    func remove(publicKey: KeyExchange.PublicKey, messageNumber: Int) throws { fatalError() }
}
