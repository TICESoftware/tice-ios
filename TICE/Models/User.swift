//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation

class User: Codable {
    let userId: UserId
    var publicSigningKey: PublicKey
    var publicName: String?

    init(userId: UserId, publicSigningKey: PublicKey, publicName: String?) {
        self.userId = userId
        self.publicSigningKey = publicSigningKey
        self.publicName = publicName
    }
}

extension User: Hashable {
    static func == (lhs: User, rhs: User) -> Bool {
        return lhs.userId == rhs.userId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(userId)
    }
}
