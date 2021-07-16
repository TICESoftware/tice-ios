//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import Swinject
import TICEAPIModels
import PromiseKit

protocol SignedInUserNotificationHandler {
    func userDidSignIn(_ signedInUser: SignedInUser)
    func userDidSignOut()
}

extension SignedInUserNotificationHandler {
    func userDidSignIn(_ signedInUser: SignedInUser) { }
    func userDidSignOut() { }
}

class SignedInUserManager: SignedInUserManagerType {

    let signedInUserStorageManager: SignedInUserStorageManagerType
    let userStorageManager: UserStorageManagerType
    let notifier: Notifier
    let tracker: TrackerType
    let container: Container
    let resolver: Swinject.Resolver

    var signedInUser: SignedInUser?

    weak var teamBroadcaster: TeamBroadcaster?
    
    var signedIn: Bool {
        signedInUser != nil
    }

    init(signedInUserStorageManager: SignedInUserStorageManagerType, userStorageManager: UserStorageManagerType, notifier: Notifier, tracker: TrackerType, container: Container, resolver: Swinject.Resolver) {
        self.signedInUserStorageManager = signedInUserStorageManager
        self.userStorageManager = userStorageManager
        self.notifier = notifier
        self.tracker = tracker
        self.container = container
        self.resolver = resolver
    }
    
    func setup() {
        self.signedInUser = signedInUserStorageManager.loadSignedInUser()
        if let signedInUser = self.signedInUser {
            didSignIn(signedInUser)
        }
        
        logger.debug("Initialized SignedInUserManager \(signedInUser == nil ? "without" : "with") stored signed in user.")
    }

    func requireSignedInUser() throws -> SignedInUser {
        guard let user = signedInUser else {
            throw SignedInUserManagerError.userNotSignedIn
        }
        return user
    }

    func signIn(_ signedInUser: SignedInUser) throws {
        self.signedInUser = signedInUser
        try signedInUserStorageManager.store(signedInUser: signedInUser)
        try userStorageManager.store(signedInUser)
        didSignIn(signedInUser)
    }

    private func didSignIn(_ signedInUser: SignedInUser) {
        container.register(SignedInUser.self, factory: { _ in signedInUser }).inObjectScope(.container)
        notifier.notify(SignedInUserNotificationHandler.self) { $0.userDidSignIn(signedInUser) }
        
        tracker.log(action: .signIn, category: .app)

        DispatchQueue.global().async {
            self.resolver.resolve(LocationManagerType.self)?.setup()
            self.resolver.resolve(TeamManagerType.self)?.setup()
            self.resolver.resolve(ConversationManagerType.self)?.registerHandler()
            self.resolver.resolve(GroupNotificationReceiverType.self)?.registerHandler()
            self.resolver.resolve(TooFewOneTimePrekeysHandlerType.self)?.registerHandler()
            self.resolver.resolve(ChatMessageReceiverType.self)?.registerHandler()
            self.resolver.resolve(UserManagerType.self)?.registerHandler()
            self.resolver.resolve(LocationSharingManagerType.self)?.registerHandler()
            self.resolver.resolve(NotificationManagerType.self)?.setup()
            
            self.resolver.resolve(WebSocketReceiver.self)?.connect()
        }
        
        logger.debug("Did sign in user \(signedInUser.userId).")
    }

    func signOut() throws {
        tracker.log(action: .signOut, category: .app)
        
        self.signedInUser = nil
        signedInUserStorageManager.deleteAllData()

        notifier.notify(SignedInUserNotificationHandler.self) { $0.userDidSignOut() }
    }

    func changePublicName(to publicName: String?) throws {
        guard let teamBroadcaster = teamBroadcaster else {
            throw SignedInUserManagerError.noBroadcaster
        }

        let signedInUser = try requireSignedInUser()
        signedInUser.publicName = publicName
        
        try signedInUserStorageManager.store(signedInUser: signedInUser)
        try userStorageManager.store(signedInUser)

        let payloadContainer = PayloadContainer(payloadType: .userUpdateV1, payload: UserUpdate(userId: signedInUser.userId))
        teamBroadcaster.sendToAllTeams(payloadContainer: payloadContainer).catch { logger.error("Error sending user update: \(String(describing: $0))") }
    }
}
