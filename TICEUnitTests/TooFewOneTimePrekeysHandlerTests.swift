//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import XCTest
import TICEAPIModels
import Cuckoo
import PromiseKit

@testable import TICE

class TooFewOneTimePrekeysHandlerTests: XCTestCase {

    var conversationCryptoMiddleware: MockConversationCryptoMiddlewareType!
    var backend: MockTICEAPI!
    var signedInUser: SignedInUser!
    var postOffice: MockPostOfficeType!
    
    var tooFewOneTimePrekeysHandler: TooFewOneTimePrekeysHandler!

    override func setUp() {
        super.setUp()

        backend = MockTICEAPI()
        signedInUser = SignedInUser(userId: UserId(), privateSigningKey: "privateSigningKey".data, publicSigningKey: Data(), publicName: "publicName")
        
        conversationCryptoMiddleware = MockConversationCryptoMiddlewareType()
        postOffice = MockPostOfficeType()

        tooFewOneTimePrekeysHandler = TooFewOneTimePrekeysHandler(conversationCryptoMiddleware: conversationCryptoMiddleware, backend: backend, signedInUser: signedInUser, postOffice: postOffice)
    }
    
    func testRegisterPostOfficeHandler() {
        stub(postOffice) { stub in
            when(stub.handlers.get).thenReturn([:])
            when(stub.handlers.set(any())).thenDoNothing()
        }
        
        tooFewOneTimePrekeysHandler.registerHandler()
        
        verify(postOffice).handlers.set(any())
    }

    func testHandleFewOneTimePrekeys() {
        let completionCalled = expectation(description: "Handler called")
        
        let userPublicKeys = UserPublicKeys(
            signingKey: "signingKey".data,
            identityKey: "identityKey".data,
            signedPrekey: "signedPrekey".data,
            prekeySignature: "prekeySignature".data,
            oneTimePrekeys: ["oneTimePrekey".data]
        )
        stub(conversationCryptoMiddleware) { stub in
            when(stub.renewHandshakeKeyMaterial(privateSigningKey: signedInUser.privateSigningKey)).thenReturn(userPublicKeys)
        }

        stub(backend) { stub in
            when(stub.updateUser(userId: signedInUser.userId, publicKeys: userPublicKeys, deviceId: nil as Data?, verificationCode: nil as String?, publicName: signedInUser.publicName)).thenReturn(Promise())
        }

        let payloadMetaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: UserId(), timestamp: Date(), collapseId: nil, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, conversationInvitation: nil)

        tooFewOneTimePrekeysHandler.handleFewOneTimePrekeys(payload: FewOneTimePrekeys(remaining: 42), metaInfo: payloadMetaInfo) { result in
            defer {
                completionCalled.fulfill()
            }

            guard result == .newData else {
                XCTFail("Invalid result.")
                return
            }
        }

        wait(for: [completionCalled])
        
        verify(conversationCryptoMiddleware).renewHandshakeKeyMaterial(privateSigningKey: signedInUser.privateSigningKey)
        verify(backend).updateUser(userId: signedInUser.userId, publicKeys: userPublicKeys, deviceId: nil as Data?, verificationCode: nil as String?, publicName: signedInUser.publicName)
    }
}
