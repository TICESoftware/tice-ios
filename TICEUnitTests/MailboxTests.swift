//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import XCTest
import TICEAPIModels
import PromiseKit
import Cuckoo

@testable import TICE

class MailboxTests: XCTestCase {

    var encoder: JSONEncoder!
    var decoder: JSONDecoder!
    var signedInUser: SignedInUser!
    var cryptoManager: MockCryptoManagerType!
    var conversationCryptoMiddleware: MockConversationCryptoMiddlewareType!
    var conversationManager: MockConversationManagerType!
    var backend: MockTICEAPI!
    var membership: Membership!
    
    var mailbox: Mailbox!
    
    var payloadContainer: PayloadContainer!
    
    let ciphertext = "ciphertext".data
    let messageKey = "messageKey".data
    let messageKeyCiphertext = "messageKeyCiphertext".data

    override func setUpWithError() throws {
        super.setUp()

        encoder = JSONEncoder.encoderWithFractionalSeconds
        decoder = JSONDecoder.decoderWithFractionalSeconds

        backend = MockTICEAPI()
        cryptoManager = MockCryptoManagerType()
        conversationCryptoMiddleware = MockConversationCryptoMiddlewareType()
        conversationManager = MockConversationManagerType()
        
        signedInUser = SignedInUser(userId: UserId(),  privateSigningKey: "privateKey".data, publicSigningKey: "publicKey".data, publicName: "publicName")

        membership = Membership(userId: UserId(), publicSigningKey: "publicSigningKey".data, groupId: GroupId(), admin: false, serverSignedMembershipCertificate: "membershipCertificate")
        
        stub(conversationManager) { stub in
            when(stub.delegate.set(any())).thenDoNothing()
        }
        
        mailbox = Mailbox(backend: backend, signedInUser: signedInUser, cryptoManager: cryptoManager, conversationManager: conversationManager, encoder: encoder)
        
        payloadContainer = PayloadContainer(payloadType: .userUpdateV1, payload: UserUpdate(userId: signedInUser.userId))
        let encodedPayloadContainer = try encoder.encode(payloadContainer)
        
        stub(cryptoManager) { stub in
            when(stub.encrypt(encodedPayloadContainer)).thenReturn((ciphertext, messageKey))
        }
    }
    
    func testSendNonCollapsingWithConversationInvitation() throws {
        sendMessage(collapsing: false, conversationExisting: false)
    }
    
    func testSendCollapsingWithConversationInvitation() throws {
        sendMessage(collapsing: true, conversationExisting: false)
    }
    
    func testSendNonCollapsingWithoutConversationInvitation() throws {
        sendMessage(collapsing: false, conversationExisting: true)
    }
    
    func testSendCollapsingWithoutConversationInvitation() throws {
        sendMessage(collapsing: true, conversationExisting: true)
    }
    
    private func sendMessage(collapsing: Bool, conversationExisting: Bool) {
        let serverSignedMembershipCertificate = "serverSignedMembershipCertificate"
        let collapseId = collapsing ? Envelope.CollapseIdentifier() : nil
        
        let conversationInvitation = collapsing ? ConversationInvitation(identityKey: "identityKey".data, ephemeralKey: "ephemeralKey".data, usedOneTimePrekey: "oneTimePrekey".data) : nil
        let expectedRecipient = Recipient(userId: membership.userId, serverSignedMembershipCertificate: membership.serverSignedMembershipCertificate, encryptedMessageKey: messageKeyCiphertext, conversationInvitation: conversationInvitation)
        
        stub(conversationManager) { stub in
            when(stub.encrypt(data: messageKey, for: membership.userId, collapsing: collapsing)).thenReturn(Promise.value(messageKeyCiphertext))
            when(stub.conversationInvitation(userId: membership.userId, collapsing: collapsing)).thenReturn(conversationInvitation)
        }
    
        stub(backend) { stub in
            when(stub.message(id: any(), senderId: signedInUser.userId, timestamp: any(), encryptedMessage: ciphertext, serverSignedMembershipCertificate: serverSignedMembershipCertificate, recipients: Set([expectedRecipient]), priority: MessagePriority.alert, collapseId: collapseId)).thenReturn(Promise())
        }
        
        let exp = expectation(description: "Completion")
        
        firstly {
            mailbox.send(payloadContainer: payloadContainer, to: [membership], serverSignedMembershipCertificate: serverSignedMembershipCertificate, priority: .alert, collapseId: collapseId)
        }.catch {
            XCTFail("\($0)")
        }.finally {
            exp.fulfill()
        }
        
        wait(for: [exp])
    }
    
    func testEncryptionFailureOneRecipient() {
        let serverSignedMembershipCertificate = "serverSignedMembershipCertificate"
        let collapseId = Envelope.CollapseIdentifier()
        
        let conversationInvitation = ConversationInvitation(identityKey: "identityKey".data, ephemeralKey: "ephemeralKey".data, usedOneTimePrekey: "oneTimePrekey".data)
        let expectedRecipient = Recipient(userId: membership.userId, serverSignedMembershipCertificate: membership.serverSignedMembershipCertificate, encryptedMessageKey: messageKeyCiphertext, conversationInvitation: conversationInvitation)
        
        stub(conversationManager) { stub in
            when(stub.encrypt(data: messageKey, for: membership.userId, collapsing: true)).thenReturn(Promise(error: CryptoManagerError.encryptionError))
            when(stub.initConversation(userId: membership.userId, collapsing: true)).thenReturn(Promise())
            when(stub.conversationInvitation(userId: membership.userId, collapsing: true)).thenReturn(conversationInvitation)
        }
    
        stub(backend) { stub in
            when(stub.message(id: any(), senderId: signedInUser.userId, timestamp: any(), encryptedMessage: ciphertext, serverSignedMembershipCertificate: serverSignedMembershipCertificate, recipients: Set([expectedRecipient]), priority: MessagePriority.alert, collapseId: collapseId)).thenReturn(Promise())
        }
        
        let exp = expectation(description: "Completion")
        
        firstly {
            mailbox.send(payloadContainer: payloadContainer, to: [membership], serverSignedMembershipCertificate: serverSignedMembershipCertificate, priority: .alert, collapseId: collapseId)
        }.catch {
            XCTFail("\($0)")
        }.finally {
            exp.fulfill()
        }
        
        wait(for: [exp])
    }
    
    // Disable test while Cuckoo bugfix is pending: https://github.com/Brightify/Cuckoo/pull/351
    
//    func testEncryptionFailureTwoRecipients() {
//        let serverSignedMembershipCertificate = "serverSignedMembershipCertificate"
//        let collapseId = Envelope.CollapseIdentifier()
//
//        let expectedRecipientEncryptionSuccess = Recipient(userId: membership.userId, serverSignedMembershipCertificate: membership.serverSignedMembershipCertificate, encryptedMessageKey: messageKeyCiphertext, conversationInvitation: nil)
//
//        let membershipEncryptionFailure = Membership(userId: UserId(), publicSigningKey: "secondPublicSigningKey".data, groupId: membership.groupId, admin: false, serverSignedMembershipCertificate: "secondServerSignedMembershipCertificate")
//        let conversationInvitation = ConversationInvitation(identityKey: "identityKey".data, ephemeralKey: "ephemeralKey".data, usedOneTimePrekey: "oneTimePrekey".data)
//        let expectedRecipientEncryptionFailure = Recipient(userId: membershipEncryptionFailure.userId, serverSignedMembershipCertificate: membershipEncryptionFailure.serverSignedMembershipCertificate, encryptedMessageKey: "encryptedMessageKeyAfterFailure".data, conversationInvitation: conversationInvitation)
//
//        stub(conversationManager) { stub in
//            when(stub.encrypt(data: messageKey, for: membership.userId, collapsing: true)).thenReturn(Promise.value(messageKeyCiphertext))
//            when(stub.encrypt(data: messageKey, for: membershipEncryptionFailure.userId, collapsing: true)).thenReturn(Promise(error: CryptoManagerError.encryptionError))
//
//            when(stub.initConversation(userId: membershipEncryptionFailure.userId, collapsing: true)).thenReturn(Promise())
//
//            when(stub.conversationInvitation(userId: membership.userId, collapsing: true)).thenReturn(nil)
//            when(stub.conversationInvitation(userId: membershipEncryptionFailure.userId, collapsing: true)).thenReturn(conversationInvitation)
//        }
//
//        stub(backend) { stub in
//            when(stub.message(id: any(), senderId: signedInUser.userId, timestamp: any(), encryptedMessage: ciphertext, serverSignedMembershipCertificate: serverSignedMembershipCertificate, recipients: Set([expectedRecipientEncryptionSuccess]), priority: MessagePriority.alert, collapseId: collapseId)).thenReturn(Promise())
//            when(stub.message(id: any(), senderId: signedInUser.userId, timestamp: any(), encryptedMessage: ciphertext, serverSignedMembershipCertificate: serverSignedMembershipCertificate, recipients: Set([expectedRecipientEncryptionFailure]), priority: MessagePriority.alert, collapseId: collapseId)).thenReturn(Promise())
//        }
//
//        let exp = expectation(description: "Completion")
//
//        firstly {
//            mailbox.send(payloadContainer: payloadContainer, to: [membership, membershipEncryptionFailure], serverSignedMembershipCertificate: serverSignedMembershipCertificate, priority: .alert, collapseId: collapseId)
//        }.catch {
//            XCTFail("\($0)")
//        }.finally {
//            exp.fulfill()
//        }
//
//        wait(for: [exp])
//    }
}
