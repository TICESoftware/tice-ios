//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import Valet

enum SignedInUserStorageManagerError: LocalizedError {
    case valetError

    var errorDescription: String? {
        switch self {
        case .valetError: return L10n.Error.SignedInUserStorageManager.valetError
        }
    }
}

class SignedInUserStorageManager: SignedInUserStorageManagerType {

    let userDefaults: UserDefaults
    let valet: Valet

    enum StorageKey: String {
        case signingKey
        case signedInUserUserId
        case signedInUserPublicName
    }

    init(userDefaults: UserDefaults, valet: Valet) {
        self.userDefaults = userDefaults
        self.valet = valet
    }

    func store(signedInUser: SignedInUser) throws {
        guard valet.set(object: signedInUser.privateSigningKey, forKey: StorageKey.signingKey.rawValue) else {
            logger.error("Could not store private signing key in keychain.")
            throw SignedInUserStorageManagerError.valetError
        }
        userDefaults.set(signedInUser.publicSigningKey, forKey: StorageKey.signingKey.rawValue)

        userDefaults.set(signedInUser.userId.uuidString, forKey: StorageKey.signedInUserUserId.rawValue)
        userDefaults.set(signedInUser.publicName, forKey: StorageKey.signedInUserPublicName.rawValue)
    }

    func loadSignedInUser() -> SignedInUser? {
        if CommandLine.arguments.contains("UITESTING") {
            return nil
        }

        guard let userIdString = userDefaults.string(forKey: StorageKey.signedInUserUserId.rawValue),
            let userId = UserId(uuidString: userIdString),
            let publicSigningKey = userDefaults.data(forKey: StorageKey.signingKey.rawValue),
            let privateSigninKey = valet.object(forKey: StorageKey.signingKey.rawValue) else {
                logger.info("Could not load signed in user.")
                return nil
        }

        let signingKeyPair = KeyPair(privateKey: privateSigninKey, publicKey: publicSigningKey)
        let publicName = userDefaults.string(forKey: StorageKey.signedInUserPublicName.rawValue)

        return SignedInUser(userId: userId, privateSigningKey: signingKeyPair.privateKey, publicSigningKey: signingKeyPair.publicKey, publicName: publicName)
    }
}

extension SignedInUserStorageManager: DeletableStorageManagerType {
    func deleteAllData() {
        valet.removeObject(forKey: StorageKey.signingKey.rawValue)
        userDefaults.removeObject(forKey: StorageKey.signingKey.rawValue)
        userDefaults.removeObject(forKey: StorageKey.signedInUserUserId.rawValue)
        userDefaults.removeObject(forKey: StorageKey.signedInUserPublicName.rawValue)
    }
}
