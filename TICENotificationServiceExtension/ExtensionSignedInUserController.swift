//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import Swinject

enum ExtensionSignedInUserManagerError: LocalizedError {
    case notAvailableInExtension

    var errorDescription: String? {
        switch self {
        case .notAvailableInExtension: return "The operation is not available in the extension."
        }
    }
}

class ExtensionSignedInUserManager: SignedInUserManagerType {
    let container: Container
    let storageManager: SignedInUserStorageManagerType
    
    var signedInUser: SignedInUser?
    var teamBroadcaster: TeamBroadcaster?
    
    var signedIn: Bool {
        signedInUser != nil
    }

    init(container: Container, storageManager: SignedInUserStorageManagerType) {
        self.container = container
        self.storageManager = storageManager
    }
    
    func setup() {
        self.signedInUser = storageManager.loadSignedInUser()

        guard let signedInUser = signedInUser else {
            logger.error("Could not access signed in user.")
            return
        }

        container.register(SignedInUser.self, factory: { _ in signedInUser }).inObjectScope(.container)
    }

    func requireSignedInUser() throws -> SignedInUser {
        guard let user = signedInUser else {
            throw SignedInUserManagerError.userNotSignedIn
        }
        return user
    }

    func signIn(_ signedInUser: SignedInUser) throws {
        throw ExtensionSignedInUserManagerError.notAvailableInExtension
    }

    func signOut() throws {
        throw ExtensionSignedInUserManagerError.notAvailableInExtension
    }

    func changePublicName(to publicName: String?) throws {
        throw ExtensionSignedInUserManagerError.notAvailableInExtension
    }
}
