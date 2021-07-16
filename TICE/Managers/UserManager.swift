//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels
import PromiseKit

protocol UserUpdateNotificationHandler {
    func didUpdateUser(userId: UserId)
}

enum UserManagerError: LocalizedError {
    case couldNotAccessLocalUser

    var errorDescription: String? {
        switch self {
        case .couldNotAccessLocalUser: return "Could not access local user."
        }
    }
}

class UserManager: UserManagerType {
    let storageManager: UserStorageManagerType
    let backend: TICEAPI
    weak var postOffice: PostOfficeType?
    let signedInUser: User
    let notifier: Notifier

    init(storageManager: UserStorageManagerType, backend: TICEAPI, postOffice: PostOfficeType, signedInUser: SignedInUser, notifier: Notifier) {
        self.storageManager = storageManager
        self.backend = backend
        self.postOffice = postOffice
        self.signedInUser = signedInUser
		self.notifier = notifier
    }
    
    func registerHandler() {
        self.postOffice?.handlers[.userUpdateV1] = handleUserUpdate(payload:metaInfo:completion:)
    }

    deinit {
        self.postOffice?.handlers[.userUpdateV1] = nil
    }

    func user(_ userId: UserId) -> User? {
        if signedInUser.userId == userId {
            return signedInUser
        }

        do {
            return try storageManager.loadUser(userId: userId)
        } catch {
            logger.error("Error loading user \(userId): \(String(describing: error))")
            return nil
        }
    }

    func getUser(_ userId: UserId) -> Promise<User> {
        if let user = user(userId) {
            return .value(user)
        }

        logger.debug("No valid cache entry for user \(userId). Fetching.")
        return fetchUser(userId)
    }

    private func fetchUser(_ userId: UserId) -> Promise<User> {
        return firstly {
            backend.getUser(userId: userId)
        }.map { getUserResponse in
            let user = User(userId: userId, publicSigningKey: getUserResponse.publicSigningKey, publicName: getUserResponse.publicName)
            try self.storageManager.store(user)
            self.notifier.notify(UserUpdateNotificationHandler.self) { $0.didUpdateUser(userId: userId) }
            return user
        }
    }

    func reloadUsers() -> Promise<Void> {
        firstly { () -> Promise<Void> in
            let reloadPromises = try storageManager.loadUsers().map { fetchUser($0.userId) }
            return when(resolved: reloadPromises).asVoid()
        }
    }

    func handleUserUpdate(payload: Payload, metaInfo: PayloadMetaInfo, completion: PostOfficeType.PayloadHandler?) {
        guard let payload = payload as? UserUpdate else {
            logger.error("Invalid payload type. Expected user update.")
            completion?(.failed)
            return
        }
        fetchUser(payload.userId).catch { logger.error("User Update for \(payload.userId) failed: \(String(describing: $0))") }
        completion?(.newData)
    }
}
