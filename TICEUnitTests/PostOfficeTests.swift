//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import XCTest
import Foundation
import TICEAPIModels
import Shouter
import PromiseKit
import Cuckoo

@testable import TICE

class PostOfficeTests: XCTestCase {
    var storageManager: MockPostOfficeStorageManagerType!
    var backend: MockTICEAPI!

    var userId: UserId!
    var groupId: GroupId!

    var sampleEnvelope: Envelope!

    var postOffice: PostOffice!

    override func setUp() {
        super.setUp()

        userId = UserId()
        groupId = GroupId()

        let payloadContainer = PayloadContainer(payloadType: .encryptedPayloadContainerV1, payload: EncryptedPayloadContainer(ciphertext: "C".data, encryptedKey: "K".data))
        sampleEnvelope = Envelope(id: MessageId(), senderId: userId, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil,timestamp: Date(), serverTimestamp: Date(), collapseId: nil, conversationInvitation: nil, payloadContainer: payloadContainer)

        storageManager = MockPostOfficeStorageManagerType()
        backend = MockTICEAPI()

        postOffice = PostOffice(storageManager: storageManager, backend: backend, envelopeCacheTime: 10.0)
    }
    
    func testCallingDecodingStrategy() {
        stub(storageManager) { stub in
            when(stub.deleteCacheRecordsOlderThan(any())).thenDoNothing()
            when(stub.isCached(envelope: any())).thenReturn(false)
            when(stub.updateCacheRecord(for: sampleEnvelope, state: any())).thenDoNothing()
        }
        
        let expectation = self.expectation(description: "Should call decoding strategy")
        postOffice.decodingStrategies[.encryptedPayloadContainerV1] = { payload, metaInfo in
            XCTAssert(payload is EncryptedPayloadContainer)
            XCTAssertEqual(metaInfo.senderId, self.userId)
            expectation.fulfill()
            let payloadContainer = PayloadContainer(payloadType: .groupInvitationV1, payload: GroupInvitation(groupId: self.groupId))
            return PayloadContainerBundle(payloadContainer: payloadContainer, metaInfo: metaInfo)
        }
        
        postOffice.receive(envelope: sampleEnvelope)
        wait(for: [expectation])
    }
    
    func testCallingCompletionHandlerHavingNoHandlers() {
        stub(storageManager) { stub in
            when(stub.deleteCacheRecordsOlderThan(any())).thenDoNothing()
            when(stub.isCached(envelope: any())).thenReturn(false)
            when(stub.updateCacheRecord(for: sampleEnvelope, state: any())).thenDoNothing()
        }
        
        let expectation = self.expectation(description: "Should call completion handler")
        postOffice.receive(envelope: sampleEnvelope, timeout: 2, completionHandler: { result in
            XCTAssert(result == .noData)
            expectation.fulfill()
        })
        wait(for: [expectation])
    }
    
    func testCallingHandler() {
        stub(storageManager) { stub in
            when(stub.deleteCacheRecordsOlderThan(any())).thenDoNothing()
            when(stub.isCached(envelope: any())).thenReturn(false)
            when(stub.updateCacheRecord(for: sampleEnvelope, state: any())).thenDoNothing()
        }
        
        let handlerExpectation = self.expectation(description: "Should call handler")
        postOffice.handlers[.encryptedPayloadContainerV1] = { _, _, completionHandler in
            completionHandler!(.newData)
            handlerExpectation.fulfill()
        }
        
        let receiveExpectation = self.expectation(description: "Should call completion handler")
        postOffice.receive(envelope: sampleEnvelope, timeout: 2, completionHandler: { result in
            XCTAssert(result == .newData)
            receiveExpectation.fulfill()
        })
        
        wait(for: [handlerExpectation, receiveExpectation])
    }
    
    func testNotCallingCompletionHandlerResultingInTimeOut() {
        stub(storageManager) { stub in
            when(stub.deleteCacheRecordsOlderThan(any())).thenDoNothing()
            when(stub.isCached(envelope: any())).thenReturn(false)
            when(stub.updateCacheRecord(for: sampleEnvelope, state: any())).thenDoNothing()
        }
        
        postOffice.handlers[.encryptedPayloadContainerV1] = { _, _, _ in }
        
        let receiveExpectation = self.expectation(description: "Should call completion handler")
        postOffice.receive(envelope: sampleEnvelope, timeout: 1, completionHandler: { result in
            XCTAssertEqual(result, .timeOut)
            receiveExpectation.fulfill()
        })
        
        wait(for: [receiveExpectation])
    }
    
    func testCallingHandlerOfDecodedEnvelope() {
        stub(storageManager) { stub in
            when(stub.deleteCacheRecordsOlderThan(any())).thenDoNothing()
            when(stub.isCached(envelope: any())).thenReturn(false)
            when(stub.updateCacheRecord(for: sampleEnvelope, state: any())).thenDoNothing()
        }
        
        postOffice.decodingStrategies[.encryptedPayloadContainerV1] = { payload, metaInfo in
            XCTAssert(payload is EncryptedPayloadContainer)
            let payloadContainer = PayloadContainer(payloadType: .groupInvitationV1, payload: GroupInvitation(groupId: self.groupId))
            return PayloadContainerBundle(payloadContainer: payloadContainer, metaInfo: metaInfo)
        }
        
        let receiveExpectation = self.expectation(description: "Should call completion handler")
        postOffice.handlers[.groupInvitationV1] = { _, _, completionHandler in
            receiveExpectation.fulfill()
            completionHandler?(.newData)
        }
        
        postOffice.receive(envelope: sampleEnvelope)
        wait(for: [receiveExpectation])
    }
    
    func testReceiveIsNotBlocking() {
        stub(storageManager) { stub in
            when(stub.deleteCacheRecordsOlderThan(any())).thenDoNothing()
            when(stub.isCached(envelope: any())).thenReturn(false)
            when(stub.updateCacheRecord(for: sampleEnvelope, state: any())).thenDoNothing()
        }
        
        postOffice.handlers[.encryptedPayloadContainerV1] = { _, _, _ in }

        let date = Date()
        postOffice.receive(envelope: sampleEnvelope, timeout: 10, completionHandler: { _ in }) // times out in 10s but should not block
        XCTAssert(Date().timeIntervalSince(date) < 1.0)
    }
    
    func testReceivingDuplicates() {
        stub(storageManager) { stub in
            when(stub.deleteCacheRecordsOlderThan(any())).thenDoNothing()
            when(stub.isCached(envelope: sampleEnvelope)).thenReturn(true)
        }
        
        postOffice.handlers[.encryptedPayloadContainerV1] = { _, _, completionHandler in
            completionHandler?(.newData)
        }
        
        let completionExpectation = expectation(description: "First envelope")
        
        postOffice.receive(envelope: sampleEnvelope, timeout: nil, completionHandler: { result in
            XCTAssertEqual(result, .duplicate)
            completionExpectation.fulfill()
        })
        
        wait(for: [completionExpectation])
    }

    func testDecodingError() {
        stub(storageManager) { stub in
            when(stub.deleteCacheRecordsOlderThan(any())).thenDoNothing()
            when(stub.isCached(envelope: any())).thenReturn(false)
            when(stub.updateCacheRecord(for: sampleEnvelope, state: any())).thenDoNothing()
        }
        
        postOffice.decodingStrategies[.encryptedPayloadContainerV1] = { _, _ in
            throw CryptoManagerError.decryptionError(nil)
        }

        let completion = expectation(description: "Completion")
        postOffice.receive(envelope: sampleEnvelope, timeout: 2.0) { result in
            XCTAssertEqual(result, .failed, "Invalid result")
            completion.fulfill()
        }

        wait(for: [completion])

        verify(storageManager).updateCacheRecord(for: sampleEnvelope, state: EnvelopeCacheRecord.ProcessingState.handled)
    }

    func testReceivingEnvelopeBatch() {
        stub(storageManager) { stub in
            when(stub.deleteCacheRecordsOlderThan(any())).thenDoNothing()
            when(stub.isCached(envelope: any())).thenReturn(false)
            when(stub.updateCacheRecord(for: any(), state: any())).thenDoNothing()
        }
        
        let resetExp = expectation(description: "Reset handler called.")
        let fewOneTimePrekeysExp = expectation(description: "Few one time prekeys handler called.")

        let fixedMessageId = MessageId()
        let fixedTimestamp = Date()
        let collapseIdentifier = "collapse"
        let payloadContainer = PayloadContainer(payloadType: .resetConversationV1, payload: ResetConversation())

        var envelopes: [Envelope] = []
        envelopes.append(Envelope(id: MessageId(), senderId: userId, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, timestamp: fixedTimestamp.addingTimeInterval(-20.0), serverTimestamp: fixedTimestamp, collapseId: collapseIdentifier, conversationInvitation: nil, payloadContainer: payloadContainer))
        envelopes.append(Envelope(id: MessageId(), senderId: userId, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, timestamp: Date(), serverTimestamp: Date(), collapseId: nil, conversationInvitation: nil, payloadContainer: PayloadContainer(payloadType: .fewOneTimePrekeysV1, payload: FewOneTimePrekeys(remaining: 0))))
        envelopes.append(Envelope(id: fixedMessageId, senderId: userId, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, timestamp: fixedTimestamp, serverTimestamp: fixedTimestamp, collapseId: collapseIdentifier, conversationInvitation: nil, payloadContainer: payloadContainer))
        envelopes.append(Envelope(id: MessageId(), senderId: userId, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, timestamp: fixedTimestamp.addingTimeInterval(-40.0), serverTimestamp: fixedTimestamp, collapseId: collapseIdentifier, conversationInvitation: nil, payloadContainer: payloadContainer))

        let getMessagesResponse = GetMessagesResponse(messages: envelopes)
        stub(backend) { stub in
            when(stub.getMessages()).thenReturn(Promise.value(getMessagesResponse))
        }

        postOffice.handlers[.resetConversationV1] = { payload, metaInfo, completion in
            XCTAssertEqual(metaInfo.timestamp, fixedTimestamp, "Invalid payload")
            resetExp.fulfill()
            completion?(.newData)
        }

        postOffice.handlers[.fewOneTimePrekeysV1] = { payload, metaInfo, completion in
            fewOneTimePrekeysExp.fulfill()
            completion?(.newData)
        }

        firstly {
            postOffice.fetchMessages()
        }.catch {
            XCTFail(String(describing: $0))
        }

        wait(for: [resetExp, fewOneTimePrekeysExp])
    }

    func testErrorInBatchProcessing() {
        stub(storageManager) { stub in
            when(stub.deleteCacheRecordsOlderThan(any())).thenDoNothing()
            when(stub.isCached(envelope: any())).thenReturn(false, true)
            when(stub.updateCacheRecord(for: any(), state: any())).thenDoNothing()
        }
        
        let messageId = MessageId()

        var envelopes: [Envelope] = []
        envelopes.append(Envelope(id: messageId, senderId: userId, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, timestamp: Date(), serverTimestamp: Date(), collapseId: nil, conversationInvitation: nil, payloadContainer: PayloadContainer(payloadType: .resetConversationV1, payload: ResetConversation())))
        envelopes.append(Envelope(id: messageId, senderId: userId, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, timestamp: Date(), serverTimestamp: Date(), collapseId: nil, conversationInvitation: nil, payloadContainer: PayloadContainer(payloadType: .fewOneTimePrekeysV1, payload: FewOneTimePrekeys(remaining: 0))))

        let getMessagesResponse = GetMessagesResponse(messages: envelopes)
        stub(backend) { stub in
            when(stub.getMessages()).thenReturn(Promise.value(getMessagesResponse))
        }

        let resetExp = expectation(description: "Reset handler called.")
        let fewOneTimePrekeysExp = expectation(description: "Few one time prekeys handler called.")
        fewOneTimePrekeysExp.isInverted = true

        postOffice.handlers[.resetConversationV1] = { payload, metaInfo, completion in
            resetExp.fulfill()
            completion?(.newData)
        }

        postOffice.handlers[.fewOneTimePrekeysV1] = { payload, metaInfo, completion in
            fewOneTimePrekeysExp.fulfill()
            completion?(.newData)
        }

        firstly {
            postOffice.fetchMessages()
        }.catch {
            XCTFail(String(describing: $0))
        }

        wait(for: [resetExp, fewOneTimePrekeysExp])
    }
}
