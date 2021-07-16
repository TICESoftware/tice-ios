//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import XCTest
import TICEAPIModels

@testable import TICE

class MockEnvelopReceiverDelegate: EnvelopeReceiverDelegate {
    var mockedHandler: ((Envelope, ((ReceiveEnvelopeResult) -> Void)?) -> Void)?
    
    func receive(envelope: Envelope) {
        receive(envelope: envelope, timeout: nil, completionHandler: nil)
    }
    
    func receive(envelope: Envelope, timeout: TimeInterval?, completionHandler: ((ReceiveEnvelopeResult) -> Void)?) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.mockedHandler?(envelope, completionHandler)
        }
    }
}

class PushReceiverTests: XCTestCase {

    func testReceivingEnvelopeCallingDelegate() {
        let expectation = self.expectation(description: "Should call delegate")
        let mockedDelegate = MockEnvelopReceiverDelegate()
        mockedDelegate.mockedHandler = { _, _ in
            expectation.fulfill()
        }
        
        let pushReceiver = PushReceiver(decoder: JSONDecoder(), timeout: 10.0)
        pushReceiver.delegate = mockedDelegate
        
        let userInfo: [AnyHashable: Any] = [
            "apns": 123,
            "payload": [
                "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
                "senderId": "A621E1F8-C36C-495A-93FC-0C247A3E6E5F",
                "timestamp": 1548066473,
                "serverTimestamp": 1548066474,
                "payloadContainer": [
                    "payloadType": "encryptedPayloadContainer/v1",
                    "payload": [
                        "ciphertext": "",
                        "signature": "",
                        "encryptedKey": ""
                    ]
                ]
            ]
        ]
        
        pushReceiver.didReceiveRemoteNotification(userInfo: userInfo, fetchCompletionHandler: { result in
            print(result)
        })
        
        wait(for: [expectation])
    }
    
    func testReceivingEnvelopeCallingFetchCompletion() {
        let mockedDelegate = MockEnvelopReceiverDelegate()
        mockedDelegate.mockedHandler = { _, completion in
            completion?(.newData)
        }
        
        let pushReceiver = PushReceiver(decoder: JSONDecoder(), timeout: 10.0)
        pushReceiver.delegate = mockedDelegate
        
        let userInfo: [AnyHashable: Any] = [
            "apns": 123,
            "payload": [
                "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
                "senderId": "A621E1F8-C36C-495A-93FC-0C247A3E6E5F",
                "timestamp": 1548066473,
                "serverTimestamp": 1548066474,
                "payloadContainer": [
                    "payloadType": "encryptedPayloadContainer/v1",
                    "payload": [
                        "ciphertext": "",
                        "signature": "",
                        "encryptedKey": ""
                    ]
                ]
            ]
        ]
        
        let expectation = self.expectation(description: "Should call fetch completion")
        pushReceiver.didReceiveRemoteNotification(userInfo: userInfo, fetchCompletionHandler: { result in
            XCTAssertEqual(result, .newData)
            expectation.fulfill()
        })
        
        wait(for: [expectation])
    }
    
    func testTimeout() {
        let pushReceiver = PushReceiver(decoder: JSONDecoder(), timeout: 1)
        let expectation = self.expectation(description: "Should call completion handler with .noData (time out) result")
        let completionHandler = { (result: UIBackgroundFetchResult) in // should be called exactly once
            XCTAssertEqual(result, .noData)
            expectation.fulfill()
        }
        
        let mockedDelegate = MockEnvelopReceiverDelegate()
        mockedDelegate.mockedHandler = { _, closure in // should call closure after timeout occurs
            sleep(2)
            closure?(.newData)
        }
        
        pushReceiver.delegate = mockedDelegate
        
        let userInfo: [AnyHashable: Any] = [
            "apns": 123,
            "payload": [
                "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
                "senderId": "A621E1F8-C36C-495A-93FC-0C247A3E6E5F",
                "timestamp": 1548066473,
                "serverTimestamp": 1548066474,
                "payloadContainer": [
                    "payloadType": "encryptedPayloadContainer/v1",
                    "payload": [
                        "ciphertext": "",
                        "signature": "",
                        "encryptedKey": ""
                    ]
                ]
            ]
        ]
        
        pushReceiver.didReceiveRemoteNotification(userInfo: userInfo, fetchCompletionHandler: completionHandler)
        
        wait(for: [expectation], timeout: 4)
    }
}
