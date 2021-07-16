//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import PromiseKit

enum SignedInUserManagerError: LocalizedError {
    case userNotSignedIn
    case noBroadcaster

    var errorDescription: String? {
        switch self {
        case .userNotSignedIn: return "User is not signed in"
        case .noBroadcaster: return L10n.Error.SignedInUserManager.noBroadcaster
        }
    }
}

protocol SignedInUserManagerType: AnyObject {
    var signedInUser: SignedInUser? { get }
    var signedIn: Bool { get }

    var teamBroadcaster: TeamBroadcaster? { get set }

    func setup()
    
    func signIn(_ signedInUser: SignedInUser) throws
    func signOut() throws
    func requireSignedInUser() throws -> SignedInUser
    func changePublicName(to publicName: String?) throws
}
