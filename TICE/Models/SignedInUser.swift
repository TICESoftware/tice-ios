//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation

class SignedInUser: User {
    let privateSigningKey: PrivateKey

    private enum CodingKeys: String, CodingKey {
        case privateSigningKey
    }

    init(userId: UserId, privateSigningKey: PrivateKey, publicSigningKey: PublicKey, publicName: String?) {
        self.privateSigningKey = privateSigningKey
        super.init(userId: userId, publicSigningKey: publicSigningKey, publicName: publicName)
    }

    required init(from decoder: Decoder) throws {
        fatalError("init(from:) has not been implemented")
    }
}
