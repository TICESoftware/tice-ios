//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import XCTest
import Swinject
import SwinjectAutoregistration
import Shouter
import TICEAPIModels
import Cuckoo
import PromiseKit

@testable import TICE

class SignedInUserManagerTests: XCTestCase {

    var signedInUserStorageManager: MockSignedInUserStorageManagerType!
    var userStorageManager: MockUserStorageManagerType!
    var notifier: Notifier!
    var container: Container!
    var resolver: Swinject.Resolver!
    
    var signedInUser: SignedInUser!

    var signedInUserManager: SignedInUserManager!
    
    var didSignInCallback: ((SignedInUser) -> Void)?
    var didSignOutCallback: (() -> Void)?

    override func setUp() {
        super.setUp()

        signedInUserStorageManager = MockSignedInUserStorageManagerType()
        userStorageManager = MockUserStorageManagerType()
        notifier = Shouter()
        container = Container()
        resolver = container.synchronize()
        
        signedInUser = SignedInUser(userId: UserId(), privateSigningKey: Data(), publicSigningKey: Data(), publicName: nil)
        
        signedInUserManager = SignedInUserManager(signedInUserStorageManager: signedInUserStorageManager, userStorageManager: userStorageManager, notifier: notifier, tracker: MockTracker(), container: container, resolver: resolver)

        notifier.register(SignedInUserNotificationHandler.self, observer: self)
    }

    override func tearDown() {
        notifier.unregister(SignedInUserNotificationHandler.self, observer: self)
        container.removeAll()

        super.tearDown()
    }
    
    func testSetup() throws {
        stub(signedInUserStorageManager) { stub in
            when(stub.loadSignedInUser()).thenReturn(nil, signedInUser)
        }
        
        signedInUserManager.setup()
        
        guard !signedInUserManager.signedIn else {
            XCTFail("Signed in user should not exist.")
            return
        }
        
        signedInUserManager.setup()
        
        guard let user: SignedInUser = resolver.resolve(SignedInUser.self),
              user == signedInUser else {
            XCTFail("No signed in user.")
            return
        }
    }
    
    func testRequireSignedInUser() throws {
        XCTAssertThrowsError(try signedInUserManager.requireSignedInUser()) { error in
            guard case SignedInUserManagerError.userNotSignedIn = error else {
                XCTFail("Invalid error thrown")
                return
            }
        }
        
        signedInUserManager.signedInUser = signedInUser
        
        XCTAssertEqual(try signedInUserManager.requireSignedInUser(), signedInUser)
    }

    func testSignIn() throws {
        let didSignIn = expectation(description: "Did sign in callback")
        
        let locationManagerExpectation = expectation(description: "Location manager")
        let teamManagerExpectation = expectation(description: "Team manager")
        let conversationManagerExpectation = expectation(description: "Conversation manager")
        let groupNotificationReceiverExpectation = expectation(description: "Group notification receiver")
        let tooFewOneTimePrekeysHandlerExpectation = expectation(description: "Too few one-time prekeys handler")
        let chatMessageReceiverExpectation = expectation(description: "Chat message receiver expectation")
        let usernManagerExpectation = expectation(description: "User manager")
        let notificationManagerExpectation = expectation(description: "Notification manager")
        let locationSharingManagerExpectation = expectation(description: "Location sharing manager")
        
        let locationManager = MockLocationManagerType()
        let teamManager = MockTeamManagerType()
        let conversationManager = MockConversationManagerType()
        let groupNotificationReceiver = MockGroupNotificationReceiverType()
        let tooFewOneTimePrekeysHandler = MockTooFewOneTimePrekeysHandlerType()
        let chatMessageReceiver = MockChatMessageReceiverType()
        let userManager = MockUserManagerType()
        let notificationManager = MockNotificationManagerType()
		let locationSharingManager = MockLocationSharingManagerType()
        
        container.register(LocationManagerType.self) { _ in locationManager }
        container.register(TeamManagerType.self) { _ in teamManager }
        container.register(ConversationManagerType.self) { _ in conversationManager }
        container.register(GroupNotificationReceiverType.self) { _ in groupNotificationReceiver }
        container.register(TooFewOneTimePrekeysHandlerType.self) { _ in tooFewOneTimePrekeysHandler }
        container.register(ChatMessageReceiverType.self) { _ in chatMessageReceiver }
        container.register(UserManagerType.self) { _ in userManager }
        container.register(NotificationManagerType.self) { _ in notificationManager }
        container.register(LocationSharingManagerType.self) { _ in locationSharingManager }
        
        stub(locationManager) { when($0.setup()).then { locationManagerExpectation.fulfill() } }
        stub(teamManager) { when($0.setup()).then { teamManagerExpectation.fulfill() } }
        stub(conversationManager) { when($0.registerHandler()).then { conversationManagerExpectation.fulfill() } }
        stub(groupNotificationReceiver) { when($0.registerHandler()).then { groupNotificationReceiverExpectation.fulfill() } }
        stub(tooFewOneTimePrekeysHandler) { when($0.registerHandler()).then { tooFewOneTimePrekeysHandlerExpectation.fulfill() } }
        stub(chatMessageReceiver) { when($0.registerHandler()).then { chatMessageReceiverExpectation.fulfill() } }
        stub(userManager) { when($0.registerHandler()).then { usernManagerExpectation.fulfill() } }
        stub(notificationManager) { when($0.setup()).then { notificationManagerExpectation.fulfill() } }
        stub(locationSharingManager) { when($0.registerHandler()).then { locationSharingManagerExpectation.fulfill() } }
        
        stub(signedInUserStorageManager) { stub in
            when(stub.store(signedInUser: any())).thenDoNothing()
        }
        
        stub(userStorageManager) { stub in
            when(stub.store(any())).thenDoNothing()
        }

        didSignInCallback = { user in
            XCTAssertEqual(self.signedInUser, user, "Invalid signed in user")
            didSignIn.fulfill()
        }

        try signedInUserManager.signIn(signedInUser)

        XCTAssertTrue(signedInUserManager.signedIn, "Should be signed in")
        XCTAssertEqual(signedInUserManager.signedInUser, signedInUser, "Invalid signed in user")
        XCTAssertNotNil(resolver.resolve(SignedInUser.self), "Signed in user should have been registered in Swinject")

        wait(for: [didSignIn, locationManagerExpectation, teamManagerExpectation, conversationManagerExpectation, groupNotificationReceiverExpectation, tooFewOneTimePrekeysHandlerExpectation, chatMessageReceiverExpectation, usernManagerExpectation, notificationManagerExpectation, locationSharingManagerExpectation])
        
        verify(locationManager).setup()
        verify(teamManager).setup()
        verify(conversationManager).registerHandler()
        verify(groupNotificationReceiver).registerHandler()
        verify(tooFewOneTimePrekeysHandler).registerHandler()
        verify(chatMessageReceiver).registerHandler()
        verify(userManager).registerHandler()
        verify(notificationManager).setup()
        verify(locationSharingManager).registerHandler()
        
        verify(signedInUserStorageManager).store(signedInUser: any())
    }
    
    func testSignOut() throws {
        stub(signedInUserStorageManager) { stub in
            when(stub.deleteAllData()).thenDoNothing()
        }
        
        let didSignOut = expectation(description: "Did sign out callback")
        
        didSignOutCallback = {
            didSignOut.fulfill()
        }
        
        try signedInUserManager.signOut()
        
        XCTAssertFalse(signedInUserManager.signedIn)
        
        verify(signedInUserStorageManager).deleteAllData()
        
        wait(for: [didSignOut])
    }
    
    func testChangePublicName() throws {
        XCTAssertThrowsError(try signedInUserManager.changePublicName(to: "")) { error in
            guard case SignedInUserManagerError.noBroadcaster = error else {
                XCTFail("Invalid error")
                return
            }
        }
        
        let teamBroadcaster = MockTeamBroadcaster()
        signedInUserManager.signedInUser = signedInUser
        signedInUserManager.teamBroadcaster = teamBroadcaster
        
        let payloadContainer = PayloadContainer(payloadType: .userUpdateV1, payload: UserUpdate(userId: signedInUser.userId))
        stub(teamBroadcaster) { stub in
            when(stub.sendToAllTeams(payloadContainer: payloadContainer)).thenReturn(Promise())
        }
        
        stub(signedInUserStorageManager) { stub in
            when(stub.store(signedInUser: any())).thenDoNothing()
        }
        
        stub(userStorageManager) { stub in
            when(stub.store(any())).thenDoNothing()
        }
        
        let publicName = "publicName"
        try signedInUserManager.changePublicName(to: publicName)
        
        verify(signedInUserStorageManager).store(signedInUser: any())
        verify(userStorageManager).store(any())
        verify(teamBroadcaster).sendToAllTeams(payloadContainer: payloadContainer)
    }
}

extension SignedInUserManagerTests: SignedInUserNotificationHandler {
    func userDidSignIn(_ signedInUser: SignedInUser) {
        didSignInCallback?(signedInUser)
    }

    func userDidSignOut() {
        didSignOutCallback?()
    }
}
