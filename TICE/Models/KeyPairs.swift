//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import GRDB

struct KeyPair {
    let privateKey: PrivateKey
    let publicKey: PublicKey
}

struct OneTimePrekeyPair: Codable, PersistableRecord, TableRecord, FetchableRecord {
    let publicKey: PublicKey
    let privateKey: PrivateKey

    init(keyPair: KeyPair) {
        self.publicKey = keyPair.publicKey
        self.privateKey = keyPair.privateKey
    }
}
