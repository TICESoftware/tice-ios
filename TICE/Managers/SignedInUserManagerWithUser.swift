//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation

class SignedInUserManagerWithUser: SignedInUserManagerType {
    
    var signedInUser: SignedInUser?
    var teamBroadcaster: TeamBroadcaster?
    
    init(signedInUser: SignedInUser) {
        self.signedInUser = signedInUser
    }
    
    var signedIn: Bool { signedInUser != nil }
    
    func setup() {}
    
    func signIn(_ signedInUser: SignedInUser) throws {
        self.signedInUser = signedInUser
    }
    
    func signOut() throws {
        self.signedInUser = nil
    }
    
    func requireSignedInUser() throws -> SignedInUser {
        guard let user = signedInUser else {
            throw SignedInUserManagerError.userNotSignedIn
        }
        return user
    }
    
    func changePublicName(to publicName: String?) throws {
        signedInUser?.publicName = publicName
    }
}
