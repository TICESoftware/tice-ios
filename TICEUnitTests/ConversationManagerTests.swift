//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import XCTest
import TICEAPIModels
import Shouter
import X3DH
import PromiseKit
import Cuckoo

@testable import TICE

class ConversationManagerTests: XCTestCase {
    var conversationCryptoMiddleware: MockConversationCryptoMiddlewareType!
    var authManager: MockAuthManagerType!
    var userManager: MockUserManagerType!
    var storageManager: MockConversationStorageManagerType!
    var postOffice: MockPostOfficeType!
    var backend: MockTICEAPI!
    var delegate: MockConversationManagerDelegate!
    var encoder: JSONEncoder!
    var decoder: JSONDecoder!

    var collapsingConversationIdentifier: ConversationId!
    var nonCollapsingConversationIdentifier: ConversationId!

    var conversationManager: ConversationManager!

    override func setUp() {
        super.setUp()

        encoder = JSONEncoder()
        decoder = JSONDecoder()
        let cryptoManager = MockCryptoManagerType()
        conversationCryptoMiddleware = MockConversationCryptoMiddlewareType()
        authManager = MockAuthManagerType()
        userManager = MockUserManagerType()
        storageManager = MockConversationStorageManagerType()
        postOffice = MockPostOfficeType()
        delegate = MockConversationManagerDelegate()
        backend = MockTICEAPI()

        collapsingConversationIdentifier = ConversationId()
        nonCollapsingConversationIdentifier = ConversationId()

        let tracker = MockTracker()
        conversationManager = ConversationManager(cryptoManager: cryptoManager, conversationCryptoMiddleware: conversationCryptoMiddleware, storageManager: storageManager, postOffice: postOffice, backend: backend, decoder: decoder, tracker: tracker, collapsingConversationIdentifier: collapsingConversationIdentifier, nonCollapsingConversationIdentifier: nonCollapsingConversationIdentifier, resendResetTimeout: 60.0)
        conversationManager.delegate = delegate
        
        stub(postOffice) { stub in
            when(stub.handlers.get).thenReturn([:])
            when(stub.handlers.set(any())).thenDoNothing()
            when(stub.decodingStrategies.get).thenReturn([:])
            when(stub.decodingStrategies.set(any())).thenDoNothing()
        }
    }
    
    func testHandlerRegistering() {
        conversationManager.registerHandler()
        
        let handlerArgumentCaptor = ArgumentCaptor<[PayloadContainer.PayloadType: PostOfficeType.Handler]>()
        verify(postOffice).handlers.set(handlerArgumentCaptor.capture())
        XCTAssertTrue(((handlerArgumentCaptor.value!.keys.contains(.resetConversationV1))))
        
        let decoderArgumentCaptor = ArgumentCaptor<[PayloadContainer.PayloadType: PostOfficeType.DecodingStrategy]>()
        verify(postOffice).decodingStrategies.set(decoderArgumentCaptor.capture())
        XCTAssertTrue(decoderArgumentCaptor.value!.keys.contains(.encryptedPayloadContainerV1))
    }

    func testInitializeConversation() throws {
        let userId = UserId()
        
        let getUserPublicKeysResponse = GetUserPublicKeysResponse(signingKey: Data(), identityKey: Data(), signedPrekey: Data(), prekeySignature: Data(), oneTimePrekey: Data())

        stub(backend) { stub in
            when(stub.getUserKeys(userId: userId)).thenReturn(Promise.value(getUserPublicKeysResponse))
        }
        
        let conversationInvitation = ConversationInvitation(identityKey: Data(), ephemeralKey: Data(), usedOneTimePrekey: Data())
        stub(conversationCryptoMiddleware) { stub in
            when(stub.initConversation(with: userId, conversationId: nonCollapsingConversationIdentifier, remoteIdentityKey: getUserPublicKeysResponse.identityKey, remoteSignedPrekey: getUserPublicKeysResponse.signedPrekey, remotePrekeySignature: getUserPublicKeysResponse.prekeySignature, remoteOneTimePrekey: getUserPublicKeysResponse.oneTimePrekey, remoteSigningKey: getUserPublicKeysResponse.signingKey)).thenReturn(conversationInvitation)
        }
        
        stub(storageManager) { stub in
            when(stub.storeOutboundConversationInvitation(receiverId: userId, conversationId: nonCollapsingConversationIdentifier, conversationInvitation: conversationInvitation)).thenDoNothing()
        }

        let completion = expectation(description: "Completion")
        conversationManager.initConversation(userId: userId, collapsing: false).done {
            verify(self.storageManager).storeOutboundConversationInvitation(receiverId: userId, conversationId: self.nonCollapsingConversationIdentifier, conversationInvitation: conversationInvitation)
        }.catch {
            XCTFail(String(describing: $0))
        }.finally {
            completion.fulfill()
        }
        
        wait(for: [completion])
    }

    func testEncryptUninitializedConversation() {
        let userId = UserId()
        let data = "test data".data

        let conversationInvitation = ConversationInvitation(identityKey: Data(), ephemeralKey: Data(), usedOneTimePrekey: Data())
        let encryptedData = "encryptedData".data
        
        let getUserPublicKeysResponse = GetUserPublicKeysResponse(signingKey: Data(), identityKey: Data(), signedPrekey: Data(), prekeySignature: Data(), oneTimePrekey: Data())
        
        stub(conversationCryptoMiddleware) { stub in
            when(stub.conversationExisting(userId: userId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(false)
            when(stub.initConversation(with: userId, conversationId: nonCollapsingConversationIdentifier, remoteIdentityKey: getUserPublicKeysResponse.identityKey, remoteSignedPrekey: getUserPublicKeysResponse.signedPrekey, remotePrekeySignature: getUserPublicKeysResponse.prekeySignature, remoteOneTimePrekey: getUserPublicKeysResponse.oneTimePrekey, remoteSigningKey: getUserPublicKeysResponse.signingKey)).thenReturn(conversationInvitation)
            when(stub.encrypt(data, for: userId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(encryptedData)
        }

        stub(backend) { stub in
            when(stub.getUserKeys(userId: userId)).thenReturn(Promise.value(getUserPublicKeysResponse))
        }
        
        stub(storageManager) { stub in
            when(stub.storeOutboundConversationInvitation(receiverId: userId, conversationId: nonCollapsingConversationIdentifier, conversationInvitation: conversationInvitation)).thenDoNothing()
        }

        let completion = expectation(description: "Completion")
        conversationManager.encrypt(data: data, for: userId, collapsing: false).done {
            XCTAssertEqual($0, encryptedData, "Invalid ciphertext")
        }.catch {
            XCTFail(String(describing: $0))
        }.finally {
            completion.fulfill()
        }
        
        wait(for: [completion])
    }

    func testEncryptInitializedConversation() throws {
        let userId = UserId()
        
        let encryptedData = "encryptedData".data
        stub(conversationCryptoMiddleware) { stub in
            when(stub.conversationExisting(userId: userId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(true)
            when(stub.encrypt(any(), for: userId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(encryptedData)
        }

        XCTAssertTrue(conversationManager.isConversationInitialized(userId: userId, collapsing: false), "Conversation not initialized.")

        let data = "test data".data
        conversationManager.encrypt(data: data, for: userId, collapsing: false).done {
            XCTAssertEqual($0, encryptedData, "Invalid ciphertext")
        }.catch {
            XCTFail(String(describing: $0))
        }
    }

    func testDecryptionWithConversationInvitation() throws {
        let senderId = UserId()

        let conversationInvitation = ConversationInvitation(identityKey: Data(), ephemeralKey: Data(), usedOneTimePrekey: Data())
        
        stub(storageManager) { stub in
            when(stub.deleteOutboundConversationInvitation(receiverId: senderId, conversationId: nonCollapsingConversationIdentifier)).thenDoNothing()
            when(stub.receivedReset(senderId: senderId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(nil)
            when(stub.inboundConversationInvitation(senderId: senderId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(nil)
            when(stub.storeInboundConversationInvitation(senderId: senderId, conversationId: nonCollapsingConversationIdentifier, conversationInvitation: conversationInvitation, timestamp: any())).thenDoNothing()
            when(stub.invalidConversation(userId: senderId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(nil)
        }

        let payloadContainer = PayloadContainer(payloadType: .resetConversationV1, payload: ResetConversation())
        let ciphertext = try encoder.encode(payloadContainer)
        let encryptedPayloadContainer = EncryptedPayloadContainer(ciphertext: ciphertext, encryptedKey: Data())
        
        stub(conversationCryptoMiddleware) { stub in
            when(stub.conversationFingerprint(ciphertext: encryptedPayloadContainer.encryptedKey)).thenReturn("fingerprint")
            when(stub.processConversationInvitation(conversationInvitation, from: senderId, conversationId: nonCollapsingConversationIdentifier)).thenDoNothing()
            when(stub.conversationExisting(userId: senderId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(true)
            when(stub.decrypt(encryptedData: ciphertext, encryptedSecretKey: encryptedPayloadContainer.encryptedKey, from: senderId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(try! JSONEncoder().encode(payloadContainer))
        }

        let payloadMetaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: senderId, timestamp: Date(), collapseId: nil, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, conversationInvitation: conversationInvitation)

        _ = try conversationManager.decrypt(payload: encryptedPayloadContainer, metaInfo: payloadMetaInfo)

        verify(storageManager).deleteOutboundConversationInvitation(receiverId: senderId, conversationId: nonCollapsingConversationIdentifier)
    }

    func testDecryptUninitializedConversationWithoutConversationInvitation() throws {
        let senderId = UserId()
        
        stub(storageManager) { stub in
            when(stub.receivedReset(senderId: senderId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(nil)
            when(stub.inboundConversationInvitation(senderId: senderId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(nil)
            when(stub.invalidConversation(userId: senderId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(nil)
        }
        
        let payloadContainer = PayloadContainer(payloadType: .resetConversationV1, payload: ResetConversation())
        let ciphertext = try encoder.encode(payloadContainer)
        let encryptedPayloadContainer = EncryptedPayloadContainer(ciphertext: ciphertext, encryptedKey: Data())
        
        stub(conversationCryptoMiddleware) { stub in
            when(stub.conversationFingerprint(ciphertext: encryptedPayloadContainer.encryptedKey)).thenReturn("fingerprint")
            when(stub.conversationExisting(userId: senderId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(false)
        }

        let payloadMetaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: senderId, timestamp: Date(), collapseId: nil, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, conversationInvitation: nil)

        do {
            _ = try conversationManager.decrypt(payload: encryptedPayloadContainer, metaInfo: payloadMetaInfo)
        } catch {
            guard case ConversationManagerError.invalidConversation = error else {
                XCTFail("Unexpected error: \(String(describing: error))")
                return
            }
        }
    }

    func testConversationInvalidation() throws {
        let payloadContainer = PayloadContainer(payloadType: .resetConversationV1, payload: ResetConversation())
        let ciphertext = try encoder.encode(payloadContainer)
        let encryptedPayloadContainer = EncryptedPayloadContainer(ciphertext: ciphertext, encryptedKey: Data())

        let senderId = UserId()
        let payloadMetaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: senderId, timestamp: Date(), collapseId: nil, senderServerSignedMembershipCertificate: "senderServerSignedMembershipCertificate", receiverServerSignedMembershipCertificate: "receiverServerSignedMembershipCertificate", conversationInvitation: nil)
        
        let conversationFingerprint = "fingerprint"
        let outboundConversationInvitation = ConversationInvitation(identityKey: Data(), ephemeralKey: Data(), usedOneTimePrekey: Data())
        stub(storageManager) { stub in
            when(stub.receivedReset(senderId: senderId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(nil)
            when(stub.inboundConversationInvitation(senderId: senderId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(nil)
            when(stub.invalidConversation(userId: senderId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(nil)
            when(stub.storeInvalidConversation(userId: senderId, conversationId: nonCollapsingConversationIdentifier, fingerprint: conversationFingerprint, timestamp: any(), resendResetTimeout: any())).thenDoNothing()
            when(stub.storeOutboundConversationInvitation(receiverId: senderId, conversationId: nonCollapsingConversationIdentifier, conversationInvitation: outboundConversationInvitation)).thenDoNothing()
        }

        let getUserPublicKeysResponse = GetUserPublicKeysResponse(signingKey: Data(), identityKey: Data(), signedPrekey: Data(), prekeySignature: Data(), oneTimePrekey: Data())
        
        stub(backend) { stub in
            when(stub.getUserKeys(userId: senderId)).thenReturn(Promise.value(getUserPublicKeysResponse))
        }

        let resetSent = expectation(description: "Reset sent")
        stub(delegate) { stub in
            when(stub.sendResetReply(to: senderId, receiverCertificate: payloadMetaInfo.senderServerSignedMembershipCertificate!, senderCertificate: payloadMetaInfo.receiverServerSignedMembershipCertificate!, collapseId: nil as Envelope.CollapseIdentifier?)).then { _ in
                resetSent.fulfill()
                return Promise()
            }
        }
        
        stub(conversationCryptoMiddleware) { stub in
            when(stub.conversationFingerprint(ciphertext: encryptedPayloadContainer.encryptedKey)).thenReturn(conversationFingerprint)
            when(stub.conversationExisting(userId: senderId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(true)
            when(stub.initConversation(with: senderId, conversationId: nonCollapsingConversationIdentifier, remoteIdentityKey: getUserPublicKeysResponse.identityKey, remoteSignedPrekey: getUserPublicKeysResponse.signedPrekey, remotePrekeySignature: getUserPublicKeysResponse.prekeySignature, remoteOneTimePrekey: getUserPublicKeysResponse.oneTimePrekey, remoteSigningKey: getUserPublicKeysResponse.signingKey)).thenReturn(outboundConversationInvitation)
            when(stub.decrypt(encryptedData: ciphertext, encryptedSecretKey: encryptedPayloadContainer.encryptedKey, from: senderId, conversationId: nonCollapsingConversationIdentifier)).thenThrow(ConversationCryptoMiddlewareError.decryptionError)
        }

        do {
            _ = try conversationManager.decrypt(payload: encryptedPayloadContainer, metaInfo: payloadMetaInfo)
            XCTFail("Decryption should not have succeeded.")
        } catch {
            guard case ConversationManagerError.conversationHasBeenResynced = error else {
                XCTFail("Unexpected error: \(String(describing: error))")
                return
            }
        }

        wait(for: [resetSent])
        
        verify(storageManager).storeOutboundConversationInvitation(receiverId: senderId, conversationId: nonCollapsingConversationIdentifier, conversationInvitation: outboundConversationInvitation)
    }

    func testReceiveConversationInvitationsAfterInvalidation() throws {
        let senderId = UserId()

        let invalidConversationInvitation = ConversationInvitation(identityKey: "identityKey".data, ephemeralKey: "ephemeralKey".data, usedOneTimePrekey: "oneTimePrekey".data)
        let inboundConversationInvitation = InboundConversationInvitation(senderId: senderId, conversationId: nonCollapsingConversationIdentifier, timestamp: Date().addingTimeInterval(-10.0), conversationInvitation: invalidConversationInvitation)

        let payloadContainer = PayloadContainer(payloadType: .resetConversationV1, payload: ResetConversation())
        let ciphertext = try encoder.encode(payloadContainer)
        let encryptedPayloadContainer = EncryptedPayloadContainer(ciphertext: ciphertext, encryptedKey: "encryptedKey".data)

        let payloadMetaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: senderId, timestamp: Date(), collapseId: nil, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, conversationInvitation: invalidConversationInvitation)

        let conversationFingerprint = "conversationFingerprint"
        let invalidConversation = InvalidConversation(senderId: senderId, conversationId: nonCollapsingConversationIdentifier, conversationFingerprint: conversationFingerprint, timestamp: Date().addingTimeInterval(-10.0), resendResetTimeout: Date().addingTimeInterval(50.0))

        let newConversationInvitation = ConversationInvitation(identityKey: "newIdentityKey".data, ephemeralKey: "newEphemeralKey".data, usedOneTimePrekey: "newOneTimePrekey".data)
        stub(storageManager) { stub in
            when(stub.receivedReset(senderId: senderId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(nil)
            when(stub.inboundConversationInvitation(senderId: senderId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(inboundConversationInvitation)
            when(stub.storeInboundConversationInvitation(senderId: senderId, conversationId: nonCollapsingConversationIdentifier, conversationInvitation: newConversationInvitation, timestamp: any())).thenDoNothing()
            when(stub.invalidConversation(userId: senderId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(invalidConversation)
            when(stub.deleteOutboundConversationInvitation(receiverId: senderId, conversationId: nonCollapsingConversationIdentifier)).thenDoNothing()
        }
        
        stub(conversationCryptoMiddleware) { stub in
            when(stub.conversationFingerprint(ciphertext: any())).thenReturn(conversationFingerprint, "newConversationFingerprint")
            when(stub.processConversationInvitation(newConversationInvitation, from: senderId, conversationId: nonCollapsingConversationIdentifier)).thenDoNothing()
            when(stub.conversationExisting(userId: senderId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(true)
            when(stub.decrypt(encryptedData: any(), encryptedSecretKey: any(), from: senderId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(ciphertext)
        }

        // Receive same conversation invitation

        do {
            _ = try conversationManager.decrypt(payload: encryptedPayloadContainer, metaInfo: payloadMetaInfo)
            XCTFail("Decryption should not have succeeded.")
        } catch {
            guard case ConversationManagerError.invalidConversation = error else {
                XCTFail("Unexpected error: \(String(describing: error))")
                return
            }
        }
        
        verify(conversationCryptoMiddleware, never()).processConversationInvitation(any(), from: any(), conversationId: any())

        // Receive older conversation invitation

        let olderConversationInvitation = ConversationInvitation(identityKey: "olderIdentityKey".data, ephemeralKey: "olderEphemeralKey".data, usedOneTimePrekey: "olderOneTimePrekey".data)
        let olderEncryptedPayloadContainer = EncryptedPayloadContainer(ciphertext: ciphertext, encryptedKey: "olderEncryptedKey".data)
        let olderPayloadMetaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: senderId, timestamp: Date().addingTimeInterval(-60.0), collapseId: nil, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, conversationInvitation: olderConversationInvitation)

        do {
            _ = try conversationManager.decrypt(payload: olderEncryptedPayloadContainer, metaInfo: olderPayloadMetaInfo)
            XCTFail("Decryption should not have succeeded.")
        } catch {
            guard case ConversationManagerError.invalidConversation = error else {
                XCTFail("Unexpected error: \(String(describing: error))")
                return
            }
        }
        
        verify(conversationCryptoMiddleware, never()).processConversationInvitation(any(), from: any(), conversationId: any())

        // Receive newer conversation invitation

        let newEncryptedPayloadContainer = EncryptedPayloadContainer(ciphertext: ciphertext, encryptedKey: "newEncryptedKey".data)
        let newPayloadMetaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: senderId, timestamp: Date(), collapseId: nil, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, conversationInvitation: newConversationInvitation)

        _ = try conversationManager.decrypt(payload: newEncryptedPayloadContainer, metaInfo: newPayloadMetaInfo)
        
        verify(conversationCryptoMiddleware).processConversationInvitation(newConversationInvitation, from: senderId, conversationId: nonCollapsingConversationIdentifier)
    }

    func testConversationInvitationProcessingFailure() throws {
        let payloadContainer = PayloadContainer(payloadType: .resetConversationV1, payload: ResetConversation())
        let ciphertext = try encoder.encode(payloadContainer)
        let encryptedPayloadContainer = EncryptedPayloadContainer(ciphertext: ciphertext, encryptedKey: Data())

        let senderId = UserId()
        let conversationInvitation = ConversationInvitation(identityKey: Data(), ephemeralKey: Data(), usedOneTimePrekey: Data())
        let payloadMetaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: senderId, timestamp: Date(), collapseId: nil, senderServerSignedMembershipCertificate: "senderServerSignedMembershipCertificate", receiverServerSignedMembershipCertificate: "receiverServerSignedMembershipCertificate", conversationInvitation: conversationInvitation)
        
        let conversationFingerprint = "conversationFingerprint"
        stub(storageManager) { stub in
            when(stub.receivedReset(senderId: senderId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(nil)
            when(stub.inboundConversationInvitation(senderId: senderId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(nil)
            when(stub.storeInvalidConversation(userId: senderId, conversationId: nonCollapsingConversationIdentifier, fingerprint: conversationFingerprint, timestamp: any(), resendResetTimeout: any())).thenDoNothing()
            when(stub.storeOutboundConversationInvitation(receiverId: senderId, conversationId: nonCollapsingConversationIdentifier, conversationInvitation: conversationInvitation)).thenDoNothing()
        }

        let resetSent = expectation(description: "Reset sent")
        stub(delegate) { stub in
            when(stub.sendResetReply(to: senderId, receiverCertificate: payloadMetaInfo.senderServerSignedMembershipCertificate!, senderCertificate: payloadMetaInfo.receiverServerSignedMembershipCertificate!, collapseId: nil as Envelope.CollapseIdentifier?)).then { _ in
                resetSent.fulfill()
                return Promise()
            }
        }

        let getUserPublicKeysResponse = GetUserPublicKeysResponse(signingKey: Data(), identityKey: Data(), signedPrekey: Data(), prekeySignature: Data(), oneTimePrekey: Data())
        
        stub(backend) { stub in
            when(stub.getUserKeys(userId: senderId)).thenReturn(Promise.value(getUserPublicKeysResponse))
        }
        
        stub(conversationCryptoMiddleware) { stub in
            when(stub.processConversationInvitation(conversationInvitation, from: senderId, conversationId: nonCollapsingConversationIdentifier)).thenThrow(ConversationCryptoMiddlewareError.oneTimePrekeyMissing)
            when(stub.conversationFingerprint(ciphertext: any())).thenReturn(conversationFingerprint)
            when(stub.initConversation(with: senderId, conversationId: nonCollapsingConversationIdentifier, remoteIdentityKey: getUserPublicKeysResponse.identityKey, remoteSignedPrekey: getUserPublicKeysResponse.signedPrekey, remotePrekeySignature: getUserPublicKeysResponse.prekeySignature, remoteOneTimePrekey: getUserPublicKeysResponse.oneTimePrekey, remoteSigningKey: getUserPublicKeysResponse.signingKey)).thenReturn(conversationInvitation)
        }
        
        do {
            _ = try conversationManager.decrypt(payload: encryptedPayloadContainer, metaInfo: payloadMetaInfo)
            XCTFail("Conversation invitation should not have been processed.")
        } catch {
            guard case ConversationManagerError.conversationHasBeenResynced = error else {
                XCTFail("Unexpected error: \(String(describing: error))")
                return
            }
        }

        wait(for: [resetSent])
    }

    func testResendResetNonCollapsing() throws {
        let payloadContainer = PayloadContainer(payloadType: .resetConversationV1, payload: ResetConversation())
        let ciphertext = try encoder.encode(payloadContainer)
        let encryptedPayloadContainer = EncryptedPayloadContainer(ciphertext: ciphertext, encryptedKey: Data())

        let senderId = UserId()
        let payloadMetaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: senderId, timestamp: Date(), collapseId: nil, senderServerSignedMembershipCertificate: "senderServerSignedMembershipCertificate", receiverServerSignedMembershipCertificate: "receiverServerSignedMembershipCertificate", conversationInvitation: nil)

        let getUserPublicKeysResponse = GetUserPublicKeysResponse(signingKey: Data(), identityKey: Data(), signedPrekey: Data(), prekeySignature: Data(), oneTimePrekey: Data())
        stub(backend) { stub in
            when(stub.getUserKeys(userId: senderId)).thenReturn(Promise.value(getUserPublicKeysResponse))
        }

        let conversationInvitation = ConversationInvitation(identityKey: Data(), ephemeralKey: Data(), usedOneTimePrekey: Data())
        stub(conversationCryptoMiddleware) { stub in
            when(stub.conversationExisting(userId: senderId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(true)
            when(stub.conversationFingerprint(ciphertext: any())).thenReturn("Fingerprint")
            when(stub.initConversation(with: senderId, conversationId: nonCollapsingConversationIdentifier, remoteIdentityKey: getUserPublicKeysResponse.identityKey, remoteSignedPrekey: getUserPublicKeysResponse.signedPrekey, remotePrekeySignature: getUserPublicKeysResponse.prekeySignature, remoteOneTimePrekey: getUserPublicKeysResponse.oneTimePrekey, remoteSigningKey: getUserPublicKeysResponse.signingKey)).thenReturn(conversationInvitation)
        }

        let invalidConversation = InvalidConversation(senderId: senderId, conversationId: nonCollapsingConversationIdentifier, conversationFingerprint: try conversationCryptoMiddleware.conversationFingerprint(ciphertext: encryptedPayloadContainer.encryptedKey), timestamp: Date().addingTimeInterval(-20.0), resendResetTimeout: Date().addingTimeInterval(-10.0))
        stub(storageManager) { stub in
            when(stub.receivedReset(senderId: senderId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(nil)
            when(stub.invalidConversation(userId: senderId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(invalidConversation)
            when(stub.updateInvalidConversation(userId: senderId, conversationId: nonCollapsingConversationIdentifier, resendResetTimeout: any())).thenDoNothing()
        }

        conversationManager.delegate = delegate

        let resetSent = expectation(description: "Reset sent")
        stub(delegate) { stub in
            when(stub.sendResetReply(to: senderId, receiverCertificate: payloadMetaInfo.senderServerSignedMembershipCertificate!, senderCertificate: payloadMetaInfo.receiverServerSignedMembershipCertificate!, collapseId: nil as Envelope.CollapseIdentifier?)).then { _ in
                resetSent.fulfill()
                return Promise()
            }
        }

        do {
            _ = try conversationManager.decrypt(payload: encryptedPayloadContainer, metaInfo: payloadMetaInfo)
            XCTFail("Decryption should not have succeeded.")
        } catch {
            guard case ConversationManagerError.invalidConversation = error else {
                XCTFail("Unexpected error: \(String(describing: error))")
                return
            }
        }

        wait(for: [resetSent])
    }

    func testResendResetCollapsing() throws {
        let payloadContainer = PayloadContainer(payloadType: .resetConversationV1, payload: ResetConversation())
        let ciphertext = try encoder.encode(payloadContainer)
        let encryptedPayloadContainer = EncryptedPayloadContainer(ciphertext: ciphertext, encryptedKey: Data())

        let senderId = UserId()
        let payloadMetaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: senderId, timestamp: Date(), collapseId: UUID().uuidString, senderServerSignedMembershipCertificate: "senderServerSignedMembershipCertificate", receiverServerSignedMembershipCertificate: "receiverServerSignedMembershipCertificate", conversationInvitation: nil)

        let getUserPublicKeysResponse = GetUserPublicKeysResponse(signingKey: Data(), identityKey: Data(), signedPrekey: Data(), prekeySignature: Data(), oneTimePrekey: Data())
        stub(backend) { stub in
            when(stub.getUserKeys(userId: senderId)).thenReturn(Promise.value(getUserPublicKeysResponse))
        }

        let conversationInvitation = ConversationInvitation(identityKey: Data(), ephemeralKey: Data(), usedOneTimePrekey: Data())
        stub(conversationCryptoMiddleware) { stub in
            when(stub.conversationExisting(userId: senderId, conversationId: collapsingConversationIdentifier)).thenReturn(true)
            when(stub.conversationFingerprint(ciphertext: any())).thenReturn("Fingerprint")
            when(stub.initConversation(with: senderId, conversationId: collapsingConversationIdentifier, remoteIdentityKey: getUserPublicKeysResponse.identityKey, remoteSignedPrekey: getUserPublicKeysResponse.signedPrekey, remotePrekeySignature: getUserPublicKeysResponse.prekeySignature, remoteOneTimePrekey: getUserPublicKeysResponse.oneTimePrekey, remoteSigningKey: getUserPublicKeysResponse.signingKey)).thenReturn(conversationInvitation)
        }

        let invalidConversation = InvalidConversation(senderId: senderId, conversationId: collapsingConversationIdentifier, conversationFingerprint: try conversationCryptoMiddleware.conversationFingerprint(ciphertext: encryptedPayloadContainer.encryptedKey), timestamp: Date().addingTimeInterval(-20.0), resendResetTimeout: Date().addingTimeInterval(-10.0))
        stub(storageManager) { stub in
            when(stub.receivedReset(senderId: senderId, conversationId: collapsingConversationIdentifier)).thenReturn(nil)
            when(stub.invalidConversation(userId: senderId, conversationId: collapsingConversationIdentifier)).thenReturn(invalidConversation)
            when(stub.updateInvalidConversation(userId: senderId, conversationId: collapsingConversationIdentifier, resendResetTimeout: any())).thenDoNothing()
        }

        conversationManager.delegate = delegate

        let resetSent = expectation(description: "Reset sent")
        stub(delegate) { stub in
            when(stub.sendResetReply(to: senderId, receiverCertificate: payloadMetaInfo.senderServerSignedMembershipCertificate!, senderCertificate: payloadMetaInfo.receiverServerSignedMembershipCertificate!, collapseId: payloadMetaInfo.collapseId)).then { _ in
                resetSent.fulfill()
                return Promise()
            }
        }

        do {
            _ = try conversationManager.decrypt(payload: encryptedPayloadContainer, metaInfo: payloadMetaInfo)
            XCTFail("Decryption should not have succeeded.")
        } catch {
            guard case ConversationManagerError.invalidConversation = error else {
                XCTFail("Unexpected error: \(String(describing: error))")
                return
            }
        }

        wait(for: [resetSent])
    }

    func testHandleConversationResync() {
        let senderId = UserId()
        let metaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: senderId, timestamp: Date(), collapseId: nil, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, conversationInvitation: nil)
        
        stub(storageManager) { stub in
            when(stub.storeReceivedReset(senderId: metaInfo.senderId, conversationId: nonCollapsingConversationIdentifier, timestamp: metaInfo.timestamp)).thenDoNothing()
        }
        
        let resetHandled = expectation(description: "Reset handled")
        conversationManager.handleConversationResync(payload: ResetConversation(), metaInfo: metaInfo) { result in
            XCTAssertTrue(result == .noData)
            resetHandled.fulfill()
        }

        wait(for: [resetHandled])
    }
    
    func testDiscardMessageOfResetConversation() throws {
        let senderId = UserId()
        
        stub(storageManager) { stub in
            when(stub.receivedReset(senderId: senderId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(Date())
        }
        
        stub(conversationCryptoMiddleware) { stub in
            when(stub.conversationFingerprint(ciphertext: any())).thenReturn("Fingerprint")
        }
        
        let encryptedPayloadContainer = EncryptedPayloadContainer(ciphertext: Data(), encryptedKey: Data())
        let metaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: senderId, timestamp: Date().addingTimeInterval(-10.0), collapseId: nil, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, conversationInvitation: nil)
        
        do {
            _ = try conversationManager.decrypt(payload: encryptedPayloadContainer, metaInfo: metaInfo)
            XCTFail("Decryption should not have succeeded.")
        } catch {
            guard case ConversationManagerError.invalidConversation = error else {
                XCTFail("Unexpected error: \(String(describing: error))")
                return
            }
        }
    }
    
    func testResetOverlappingPrevention() throws {
        let payloadContainer = PayloadContainer(payloadType: .resetConversationV1, payload: ResetConversation())
        let ciphertext = try encoder.encode(payloadContainer)
        let encryptedPayloadContainer = EncryptedPayloadContainer(ciphertext: ciphertext, encryptedKey: Data())

        let senderId = UserId()
        let payloadMetaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: senderId, timestamp: Date(), collapseId: nil, senderServerSignedMembershipCertificate: "senderServerSignedMembershipCertificate", receiverServerSignedMembershipCertificate: "receiverServerSignedMembershipCertificate", conversationInvitation: nil)
        
        let conversationFingerprint = "fingerprint"
        let outboundConversationInvitation = ConversationInvitation(identityKey: Data(), ephemeralKey: Data(), usedOneTimePrekey: Data())
        stub(storageManager) { stub in
            when(stub.receivedReset(senderId: senderId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(nil)
            when(stub.inboundConversationInvitation(senderId: senderId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(nil)
            when(stub.invalidConversation(userId: senderId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(nil)
            when(stub.storeInvalidConversation(userId: senderId, conversationId: nonCollapsingConversationIdentifier, fingerprint: conversationFingerprint, timestamp: any(), resendResetTimeout: any())).thenDoNothing()
            when(stub.storeOutboundConversationInvitation(receiverId: senderId, conversationId: nonCollapsingConversationIdentifier, conversationInvitation: outboundConversationInvitation)).thenDoNothing()
        }

        let getUserPublicKeysResponse = GetUserPublicKeysResponse(signingKey: Data(), identityKey: Data(), signedPrekey: Data(), prekeySignature: Data(), oneTimePrekey: Data())
        
        stub(backend) { stub in
            when(stub.getUserKeys(userId: senderId)).thenReturn(Promise.value(getUserPublicKeysResponse))
        }

        let resetSent = expectation(description: "Reset sent")
        var sendResetCalled = false
        stub(delegate) { stub in
            when(stub.sendResetReply(to: senderId, receiverCertificate: payloadMetaInfo.senderServerSignedMembershipCertificate!, senderCertificate: payloadMetaInfo.receiverServerSignedMembershipCertificate!, collapseId: nil as Envelope.CollapseIdentifier?)).then { _ in
                if !sendResetCalled {
                    sleep(1)
                    sendResetCalled = true
                }
                resetSent.fulfill()
                return Promise()
            }
        }
        
        stub(conversationCryptoMiddleware) { stub in
            when(stub.conversationFingerprint(ciphertext: encryptedPayloadContainer.encryptedKey)).thenReturn(conversationFingerprint)
            when(stub.conversationExisting(userId: senderId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(true)
            when(stub.initConversation(with: senderId, conversationId: nonCollapsingConversationIdentifier, remoteIdentityKey: getUserPublicKeysResponse.identityKey, remoteSignedPrekey: getUserPublicKeysResponse.signedPrekey, remotePrekeySignature: getUserPublicKeysResponse.prekeySignature, remoteOneTimePrekey: getUserPublicKeysResponse.oneTimePrekey, remoteSigningKey: getUserPublicKeysResponse.signingKey)).thenReturn(outboundConversationInvitation)
            when(stub.decrypt(encryptedData: ciphertext, encryptedSecretKey: encryptedPayloadContainer.encryptedKey, from: senderId, conversationId: nonCollapsingConversationIdentifier)).thenThrow(ConversationCryptoMiddlewareError.decryptionError)
        }

        for _ in 0...1 {
            do {
                _ = try conversationManager.decrypt(payload: encryptedPayloadContainer, metaInfo: payloadMetaInfo)
                XCTFail("Decryption should not have succeeded.")
            } catch {
                guard case ConversationManagerError.conversationHasBeenResynced = error else {
                    XCTFail("Unexpected error: \(String(describing: error))")
                    return
                }
            }
        }

        wait(for: [resetSent])
        
        verify(delegate).sendResetReply(to: senderId, receiverCertificate: any(), senderCertificate: any(), collapseId: any())
    }

    func testMaxSkipExceededError() throws {
        let payloadContainer = PayloadContainer(payloadType: .resetConversationV1, payload: ResetConversation())
        let ciphertext = try encoder.encode(payloadContainer)
        let encryptedPayloadContainer = EncryptedPayloadContainer(ciphertext: ciphertext, encryptedKey: Data())

        let senderId = UserId()
        let conversationInvitation = ConversationInvitation(identityKey: Data(), ephemeralKey: Data(), usedOneTimePrekey: Data())
        let payloadMetaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: senderId, timestamp: Date(), collapseId: nil, senderServerSignedMembershipCertificate: "senderServerSignedMembershipCertificate", receiverServerSignedMembershipCertificate: "receiverServerSignedMembershipCertificate", conversationInvitation: nil)

        let getUserPublicKeysResponse = GetUserPublicKeysResponse(signingKey: Data(), identityKey: Data(), signedPrekey: Data(), prekeySignature: Data(), oneTimePrekey: Data())
        stub(backend) { stub in
            when(stub.getUserKeys(userId: senderId)).thenReturn(Promise.value(getUserPublicKeysResponse))
        }

        let resetSent = expectation(description: "Reset sent")
        stub(delegate) { stub in
            when(stub.sendResetReply(to: senderId, receiverCertificate: payloadMetaInfo.senderServerSignedMembershipCertificate!, senderCertificate: payloadMetaInfo.receiverServerSignedMembershipCertificate!, collapseId: nil as Envelope.CollapseIdentifier?)).then { _ in
                resetSent.fulfill()
                return Promise()
            }
        }
        
        let conversationFingerprint = "conversationFingerprint"
        stub(storageManager) { stub in
            when(stub.receivedReset(senderId: senderId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(nil)
            when(stub.storeInvalidConversation(userId: senderId, conversationId: nonCollapsingConversationIdentifier, fingerprint: conversationFingerprint, timestamp: any(), resendResetTimeout: any())).thenDoNothing()
            when(stub.storeOutboundConversationInvitation(receiverId: senderId, conversationId: nonCollapsingConversationIdentifier, conversationInvitation: conversationInvitation)).thenDoNothing()
            when(stub.invalidConversation(userId: senderId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(nil)
            when(stub.storeInvalidConversation(userId: senderId, conversationId: nonCollapsingConversationIdentifier, fingerprint: conversationFingerprint, timestamp: any(), resendResetTimeout: any())).thenDoNothing()
        }

        stub(conversationCryptoMiddleware) { stub in
            when(stub.conversationExisting(userId: senderId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(true)
            when(stub.decrypt(encryptedData: any(), encryptedSecretKey: any(), from: any(), conversationId: any())).thenThrow(ConversationCryptoMiddlewareError.maxSkipExceeded)
            when(stub.conversationFingerprint(ciphertext: encryptedPayloadContainer.encryptedKey)).thenReturn(conversationFingerprint)
            when(stub.initConversation(with: senderId, conversationId: nonCollapsingConversationIdentifier, remoteIdentityKey: getUserPublicKeysResponse.identityKey, remoteSignedPrekey: getUserPublicKeysResponse.signedPrekey, remotePrekeySignature: getUserPublicKeysResponse.prekeySignature, remoteOneTimePrekey: getUserPublicKeysResponse.oneTimePrekey, remoteSigningKey: getUserPublicKeysResponse.signingKey)).thenReturn(conversationInvitation)
        }

        do {
            _ = try conversationManager.decrypt(payload: encryptedPayloadContainer, metaInfo: payloadMetaInfo)
            XCTFail("Decryption should not have succeeded.")
        } catch {
            guard case ConversationManagerError.conversationHasBeenResynced = error else {
                XCTFail("Unexpected error: \(String(describing: error))")
                return
            }
        }

        wait(for: [resetSent])
    }
    
    func testDiscardedObsoleteMessageError() throws {
        let payloadContainer = PayloadContainer(payloadType: .resetConversationV1, payload: ResetConversation())
        let ciphertext = try encoder.encode(payloadContainer)
        let encryptedPayloadContainer = EncryptedPayloadContainer(ciphertext: ciphertext, encryptedKey: Data())

        let senderId = UserId()
        let conversationInvitation = ConversationInvitation(identityKey: Data(), ephemeralKey: Data(), usedOneTimePrekey: Data())
        let payloadMetaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: senderId, timestamp: Date(), collapseId: nil, senderServerSignedMembershipCertificate: "senderServerSignedMembershipCertificate", receiverServerSignedMembershipCertificate: "receiverServerSignedMembershipCertificate", conversationInvitation: nil)
        
        let conversationFingerprint = "conversationFingerprint"
        stub(storageManager) { stub in
            when(stub.receivedReset(senderId: senderId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(nil)
            when(stub.storeInvalidConversation(userId: senderId, conversationId: nonCollapsingConversationIdentifier, fingerprint: conversationFingerprint, timestamp: any(), resendResetTimeout: any())).thenDoNothing()
            when(stub.storeOutboundConversationInvitation(receiverId: senderId, conversationId: nonCollapsingConversationIdentifier, conversationInvitation: conversationInvitation)).thenDoNothing()
            when(stub.invalidConversation(userId: senderId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(nil)
            when(stub.storeInvalidConversation(userId: senderId, conversationId: nonCollapsingConversationIdentifier, fingerprint: conversationFingerprint, timestamp: any(), resendResetTimeout: any())).thenDoNothing()
        }

        stub(conversationCryptoMiddleware) { stub in
            when(stub.conversationExisting(userId: senderId, conversationId: nonCollapsingConversationIdentifier)).thenReturn(true)
            when(stub.decrypt(encryptedData: any(), encryptedSecretKey: any(), from: any(), conversationId: any())).thenThrow(ConversationCryptoMiddlewareError.discardedObsoleteMessage)
            when(stub.conversationFingerprint(ciphertext: encryptedPayloadContainer.encryptedKey)).thenReturn(conversationFingerprint)
        }

        do {
            _ = try conversationManager.decrypt(payload: encryptedPayloadContainer, metaInfo: payloadMetaInfo)
            XCTFail("Decryption should not have succeeded.")
        } catch {
            guard case ConversationManagerError.obsoleteMessage = error else {
                XCTFail("Unexpected error: \(String(describing: error))")
                return
            }
        }
    }
}
