//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import DoubleRatchet
import Sodium
import Logging

protocol DoubleRatchetType {
    var sessionState: SessionState { get }
    
    func setLogger(_ logger: Logger)
    
    func encrypt(plaintext: Bytes) throws -> Message
    func decrypt(message: Message) throws -> Bytes
}

extension DoubleRatchet: DoubleRatchetType {
    func encrypt(plaintext: Bytes) throws -> Message {
        try encrypt(plaintext: plaintext, associatedData: nil)
    }
    
    func decrypt(message: Message) throws -> Bytes {
        try decrypt(message: message, associatedData: nil)
    }
}
