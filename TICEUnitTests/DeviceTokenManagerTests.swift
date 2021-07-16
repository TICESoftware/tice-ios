//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import XCTest
import TICEAPIModels
import PromiseKit
import Shouter
import Cuckoo

@testable import TICE

class DeviceTokenManagerTests: XCTestCase {

    var signedInUserManager: MockSignedInUserManagerType!
    var postOffice: MockPostOfficeType!
    var backend: MockTICEAPI!
    var signedInUser: SignedInUser!
    var notifier: Notifier!
    var remoteNotificationsRegistry: MockRemoteNotificationsRegistry!

    var deviceTokenManager: DeviceTokenManager!

    var verificationCallback: ((String) -> Void)?

    override func setUp() {
        super.setUp()

        backend = MockTICEAPI()
        postOffice = MockPostOfficeType()
        notifier = Shouter()
        remoteNotificationsRegistry = MockRemoteNotificationsRegistry()

        signedInUserManager = MockSignedInUserManagerType()
        signedInUser = SignedInUser(userId: UserId(), privateSigningKey: Data(), publicSigningKey: Data(), publicName: "publicName")

        deviceTokenManager = DeviceTokenManager(signedInUserManager: signedInUserManager, postOffice: postOffice, backend: backend, notifier: notifier)
        
        stub(remoteNotificationsRegistry) { stub in
            when(stub.registerForRemoteNotifications()).thenDoNothing()
        }
        
        stub(postOffice) { stub in
            when(stub.handlers.get).thenReturn([:])
            when(stub.handlers.set(any())).thenDoNothing()
        }
    }

    func testRegisterHandler() {
        deviceTokenManager.registerHandler()

        verify(postOffice).handlers.set(any())
    }

    func testProcessingDeviceToken() {
        let token = "token".data
        deviceTokenManager.processDeviceToken(token)
        XCTAssertEqual(deviceTokenManager.lastDeviceToken, token, "Invalid token")
    }
    
    private func registerDevice(deviceToken: Data, verificationCode: String) {
        var handler: ((Payload, PayloadMetaInfo, ((ReceiveEnvelopeResult) -> Void)?) -> Void)!
        
        stub(postOffice) { stub in
            when(stub.handlers.set(any())).then { handlers in
                guard let verificationMessageHandler = handlers[.verificationMessageV1] else {
                    XCTFail()
                    return
                }
                handler = verificationMessageHandler
            }
        }
        
        deviceTokenManager.registerHandler()
        
        stub(backend) { stub in
            when(stub.verify(deviceId: deviceToken)).thenReturn(Promise())
        }
        
        let completion = expectation(description: "Completion")
        firstly { () -> Promise<DeviceVerification> in
            deviceTokenManager.registerDevice(remoteNotificationsRegistry: remoteNotificationsRegistry, forceRefresh: true)
        }.done { deviceVerification in
            XCTAssertEqual(deviceVerification.deviceToken, deviceToken, "Invalid token")
            XCTAssertEqual(deviceVerification.verificationCode, verificationCode, "Invalid verification token")
        }.catch { error in
            XCTFail(String(describing: error))
        }.finally {
            completion.fulfill()
        }
        
        deviceTokenManager.processDeviceToken(deviceToken)
        
        let payload = VerificationMessage(verificationCode: verificationCode)
        let metaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: UserId(), timestamp: Date(), collapseId: nil, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, conversationInvitation: nil)

        let verificationCompletion = expectation(description: "Verification Completion")
        
        handler(payload, metaInfo) { result in
            XCTAssertEqual(result, .newData, "Invalid result")
            verificationCompletion.fulfill()
        }

        wait(for: [verificationCompletion, completion])
    }

    func testRegisterDeviceUserNotSignedIn() {
        stub(signedInUserManager) { stub in
            when(stub.signedInUser.get).thenReturn(nil)
        }
        
        let token = "token".data
        let verificationCode = "424-242"
        
        registerDevice(deviceToken: token, verificationCode: verificationCode)
        
        verify(remoteNotificationsRegistry).registerForRemoteNotifications()
        verify(backend).verify(deviceId: token)
    }
    
    func testRegisterDeviceUserSignedIn() {
        let signedInUser = SignedInUser(userId: UserId(), privateSigningKey: Data(), publicSigningKey: Data(), publicName: "publicName")
        stub(signedInUserManager) { stub in
            when(stub.signedInUser.get).thenReturn(signedInUser)
        }
        
        let token = "token".data
        let verificationCode = "424-242"
        
        stub(backend) { stub in
            when(stub.updateUser(userId: signedInUser.userId, publicKeys: nil as UserPublicKeys?, deviceId: token, verificationCode: verificationCode, publicName: signedInUser.publicName)).thenReturn(Promise())
        }
        
        registerDevice(deviceToken: token, verificationCode: verificationCode)
        
        verify(remoteNotificationsRegistry).registerForRemoteNotifications()
        verify(backend).verify(deviceId: token)
        verify(backend).updateUser(userId: signedInUser.userId, publicKeys: nil as UserPublicKeys?, deviceId: token, verificationCode: verificationCode, publicName: signedInUser.publicName)
    }
}
