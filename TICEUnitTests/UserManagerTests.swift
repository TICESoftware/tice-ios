//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import XCTest
import TICEAPIModels
import Shouter
import PromiseKit
import Valet
import Cuckoo

@testable import TICE

class UserManagerTests: XCTestCase {

    var storageManager: MockUserStorageManagerType!
    var backend: MockTICEAPI!
    var postOffice: MockPostOfficeType!
    var signedInUser: SignedInUser!

    var user: User!

    var userManager: UserManager!

    override func setUp() {
        super.setUp()
        
        backend = MockTICEAPI()
        postOffice = MockPostOfficeType()
        signedInUser = SignedInUser(userId: UserId(), privateSigningKey: Data(), publicSigningKey: Data(), publicName: "SignedInUser")

        storageManager = MockUserStorageManagerType()
        let notifier = Shouter()
        userManager = UserManager(storageManager: storageManager, backend: backend, postOffice: postOffice, signedInUser: signedInUser, notifier: notifier)

        user = User(userId: UserId(), publicSigningKey: "publicKey".data, publicName: "publicName")
    }
    
    func testRegistering() {
        stub(postOffice) { stub in
            when(stub.handlers.get).thenReturn([:])
            when(stub.handlers.set(any())).thenDoNothing()
        }
        
        userManager.registerHandler()
        
        verify(postOffice).handlers.set(any())
    }

    func testGetUserNotStored() {
        let exp = expectation(description: "Completion")
        
        stub(storageManager) { stub in
            when(stub.loadUser(userId: user.userId)).thenReturn(nil)
            when(stub.store(user)).thenDoNothing()
        }

        let userResponse = GetUserResponse(userId: user.userId, publicSigningKey: user.publicSigningKey, publicName: user.publicName)
        stub(backend) { stub in
            when(stub.getUser(userId: user.userId)).thenReturn(Promise.value(userResponse))
        }
        
        firstly {
            userManager.getUser(user.userId)
        }.done { user in
            XCTAssertEqual(user, self.user, "Invalid user")

            verify(self.storageManager).store(self.user)
        }.catch {
            XCTFail(String(describing: $0))
        }.finally {
            exp.fulfill()
        }

        wait(for: [exp])
    }

    func testLoadUserNotStored() {
        stub(storageManager) { stub in
            when(stub.loadUser(userId: user.userId)).thenReturn(nil)
        }
        XCTAssertNil(userManager.user(user.userId))
    }

    func testGetStoredUser() {
        let exp = expectation(description: "Completion")
        
        stub(storageManager) { stub in
            when(stub.loadUser(userId: user.userId)).thenReturn(user)
        }

        firstly {
            userManager.getUser(user.userId)
        }.done { user in
            XCTAssertEqual(user, self.user, "Invalid user")
        }.catch {
            XCTFail(String(describing: $0))
        }.finally {
            exp.fulfill()
        }

        wait(for: [exp])
    }
    
    func testloadSignedInUser() {
        XCTAssertEqual(userManager.user(signedInUser.userId), signedInUser)
    }
    
    func testGetSignedInUser() {
        let exp = expectation(description: "Completion")

        firstly {
            userManager.getUser(signedInUser.userId)
        }.done { user in
            XCTAssertEqual(user, self.signedInUser, "Invalid user")
        }.catch {
            XCTFail(String(describing: $0))
        }.finally {
            exp.fulfill()
        }

        wait(for: [exp])
    }

    func testReloadAllUsers() {
        let exp = expectation(description: "Completion")
        
        stub(storageManager) { stub in
            when(stub.loadUsers()).thenReturn([user])
            when(stub.store(user)).thenDoNothing()
        }

        let userResponse = GetUserResponse(userId: user.userId, publicSigningKey: user.publicSigningKey, publicName: user.publicName)
        stub(backend) { stub in
            when(stub.getUser(userId: user.userId)).thenReturn(Promise.value(userResponse))
        }
        
        firstly {
            userManager.reloadUsers()
        }.done {
            verify(self.storageManager).store(self.user)
        }.catch {
            XCTFail(String(describing: $0))
        }.finally {
            exp.fulfill()
        }

        wait(for: [exp])
    }
    
    func testHandlingUserUpdate() {
        let exp = expectation(description: "Completion")
        
        let userResponse = GetUserResponse(userId: user.userId, publicSigningKey: user.publicSigningKey, publicName: user.publicName)
        stub(backend) { stub in
            when(stub.getUser(userId: user.userId)).thenReturn(Promise.value(userResponse))
        }
        
        stub(storageManager) { stub in
            when(stub.store(user)).thenDoNothing()
        }
        
        let payloadMetaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: user.userId, timestamp: Date(), collapseId: nil, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, conversationInvitation: nil)
        let payload = UserUpdate(userId: user.userId)
        userManager.handleUserUpdate(payload: payload, metaInfo: payloadMetaInfo) { result in
            XCTAssertEqual(result, .newData, "Invalid completion result")
            exp.fulfill()
        }
        
        wait(for: [exp])
        
        verify(self.storageManager).store(self.user)
    }
}
