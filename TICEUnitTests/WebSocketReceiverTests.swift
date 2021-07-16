//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//

import XCTest
import TICEAPIModels
import Shouter
import Starscream
import Cuckoo

@testable import TICE

class WebSocketReceiverTests: XCTestCase {
    
    var webSocket: MockWebSocketType!
    var signedInUserManager: MockSignedInUserManagerType!
    var authManager: MockAuthManagerType!
    
    var webSocketReceiver: WebSocketReceiver!
    
    var receiveCallback: ((Envelope) -> ())?
    
    override func setUp() {
        super.setUp()
        
        webSocket = MockWebSocketType()
        signedInUserManager = MockSignedInUserManagerType()
        authManager = MockAuthManagerType()
        
        let decoder = JSONDecoder()
        let notifier = Shouter()
        
        stub(webSocket) { stub in
            when(stub.delegate.set(any())).thenDoNothing()
        }
        
        webSocketReceiver = WebSocketReceiver(webSocket: webSocket, signedInUserManager: signedInUserManager, authManager: authManager, decoder: decoder, notifier: notifier, reconnectTime: 1.0)
    }
    
    override func tearDown() {
        super.tearDown()
        
        receiveCallback = nil
    }
    
    func testConnectAlreadyConnected() {
        stub(webSocket) { stub in
            when(stub.isConnected.get).thenReturn(true)
        }
        
        webSocketReceiver.connect()
        
        verify(webSocket, never()).connect()
    }
    
    func testConnectNotSignedIn() {
        stub(webSocket) { stub in
            when(stub.isConnected.get).thenReturn(false)
        }
        
        stub(signedInUserManager) { stub in
            when(stub.signedInUser.get).thenReturn(nil)
        }
        
        webSocketReceiver.connect()
        
        verify(webSocket, never()).connect()
    }
    
    func testConnect() {
        let authHeader = "authHeader"
        let defaultRequest = URLRequest(url: URL(string: "http://example.com")!)
        stub(webSocket) { stub in
            when(stub.isConnected.get).thenReturn(false)
            when(stub.connect()).thenDoNothing()
            when(stub.request.get).thenReturn(defaultRequest)
            when(stub.request.set(any())).then { request in
                XCTAssertEqual(request.url, defaultRequest.url)
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Authorization"), authHeader)
            }
        }
        
        let signedInUser = SignedInUser(userId: UserId(), privateSigningKey: "privateKey".data, publicSigningKey: "publicKey".data, publicName: nil)
        stub(signedInUserManager) { stub in
            when(stub.signedInUser.get).thenReturn(signedInUser)
        }
        
        stub(authManager) { stub in
            when(stub.generateAuthHeader(signingKey: signedInUser.privateSigningKey, userId: signedInUser.userId)).thenReturn(authHeader)
        }
        
        webSocketReceiver.connect()
        
        verify(webSocket).request.set(any())
        verify(webSocket).connect()
    }
    
    func testDisconnect() {
        stub(webSocket) { stub in
            when(stub.disconnect()).thenDoNothing()
        }
        
        webSocketReceiver.disconnect()
        
        verify(webSocket).disconnect()
    }
    
    func testUserSignsInNotConnected() {
        let defaultRequest = URLRequest(url: URL(string: "http://example.com")!)
        stub(webSocket) { stub in
            when(stub.isConnected.get).thenReturn(false)
            when(stub.connect()).thenDoNothing()
            when(stub.request.get).thenReturn(defaultRequest)
            when(stub.request.set(any())).thenDoNothing()
        }
        
        let signedInUser = SignedInUser(userId: UserId(), privateSigningKey: "privateKey".data, publicSigningKey: "publicKey".data, publicName: nil)
        stub(signedInUserManager) { stub in
            when(stub.signedInUser.get).thenReturn(nil, signedInUser)
        }
        
        stub(authManager) { stub in
            when(stub.generateAuthHeader(signingKey: signedInUser.privateSigningKey, userId: signedInUser.userId)).thenReturn("authHeader")
        }
        
        webSocketReceiver.connect() // Is called on app launch
        webSocketReceiver.userDidSignIn(signedInUser)
        
        verify(webSocket).request.set(any())
        verify(webSocket).connect()
    }
    
    func testUserSignsInAlreadyConnected() {
        let defaultRequest = URLRequest(url: URL(string: "http://example.com")!)
        stub(webSocket) { stub in
            when(stub.isConnected.get).thenReturn(false, true, false)
            when(stub.connect()).thenDoNothing()
            when(stub.disconnect()).thenDoNothing()
            when(stub.request.get).thenReturn(defaultRequest)
            when(stub.request.set(any())).thenDoNothing()
        }
        
        let signedInUser = SignedInUser(userId: UserId(), privateSigningKey: "privateKey".data, publicSigningKey: "publicKey".data, publicName: nil)
        stub(signedInUserManager) { stub in
            when(stub.signedInUser.get).thenReturn(nil, signedInUser)
        }
        
        stub(authManager) { stub in
            when(stub.generateAuthHeader(signingKey: signedInUser.privateSigningKey, userId: signedInUser.userId)).thenReturn("authHeader")
        }
        
        webSocketReceiver.connect() // Is called on app launch
        webSocketReceiver.userDidSignIn(signedInUser)
        
        verify(webSocket).request.set(any())
        verify(webSocket).disconnect()
        verify(webSocket).connect()
    }
    
    func testUserSignsOut() {
        var defaultRequest = URLRequest(url: URL(string: "http://example.com")!)
        defaultRequest.addValue("authHeader", forHTTPHeaderField: "X-Authorization")
        
        stub(webSocket) { stub in
            when(stub.disconnect()).thenDoNothing()
            when(stub.request.get).thenReturn(defaultRequest)
            when(stub.request.set(any())).then { request in
                XCTAssertEqual(request.url, defaultRequest.url)
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Authorization"), nil)
            }
        }
        
        webSocketReceiver.userDidSignOut()
        
        verify(webSocket).request.set(any())
        verify(webSocket).disconnect()
    }

    func testWebsocketReconnectsAfterGettingDisconnected() {
        let exp = expectation(description: "Tried to connect")
        let defaultRequest = URLRequest(url: URL(string: "http://example.com")!)
        stub(webSocket) { stub in
            when(stub.connect()).thenDoNothing()
            when(stub.isConnected.get).thenReturn(false)
            when(stub.request.get).thenReturn(defaultRequest)
            when(stub.request.set(any())).thenDoNothing()
        }
        
        let signedInUser = SignedInUser(userId: UserId(), privateSigningKey: "privateKey".data, publicSigningKey: "publicKey".data, publicName: nil)
        stub(signedInUserManager) { stub in
            when(stub.signedInUser.get).thenReturn(nil, signedInUser)
        }
        
        stub(authManager) { stub in
            when(stub.generateAuthHeader(signingKey: signedInUser.privateSigningKey, userId: signedInUser.userId)).thenReturn("authHeader")
        }
        
        webSocketReceiver.connect()
        
        webSocketReceiver.websocketDidDisconnect(socket: MockWebSocketClient(), error: nil)
        
        stub(webSocket) { stub in
            when(stub.connect()).then { _ in exp.fulfill() }
        }
        wait(for: [exp])
    }
    
    func testWebsocketDoesNotReconnectAfterDisconnectingOurselves() {

        let defaultRequest = URLRequest(url: URL(string: "http://example.com")!)
        stub(webSocket) { stub in
            when(stub.connect()).thenDoNothing()
            when(stub.isConnected.get).thenReturn(false)
            when(stub.request.get).thenReturn(defaultRequest)
            when(stub.request.set(any())).thenDoNothing()
            when(stub.disconnect()).thenDoNothing()
        }
        
        let signedInUser = SignedInUser(userId: UserId(), privateSigningKey: "privateKey".data, publicSigningKey: "publicKey".data, publicName: nil)
        stub(signedInUserManager) { stub in
            when(stub.signedInUser.get).thenReturn(nil, signedInUser)
        }
        
        stub(authManager) { stub in
            when(stub.generateAuthHeader(signingKey: signedInUser.privateSigningKey, userId: signedInUser.userId)).thenReturn("authHeader")
        }
        
        webSocketReceiver.connect()
        webSocketReceiver.websocketDidConnect(socket: MockWebSocketClient())
        
        webSocketReceiver.disconnect()
        webSocketReceiver.websocketDidDisconnect(socket: MockWebSocketClient(), error: nil)
        
        let exp = expectation(description: "Tried to connect")
        exp.isInverted = true
        
        stub(webSocket) { stub in
            when(stub.connect()).then { _ in exp.fulfill() }
        }
        wait(for: [exp])
    }
    
    func testReceiveText() throws {
        let envelope = Envelope(
            id: MessageId(),
            senderId: UserId(),
            senderServerSignedMembershipCertificate: nil,
            receiverServerSignedMembershipCertificate: nil,
            timestamp: Date(),
            serverTimestamp: Date(),
            collapseId: nil,
            conversationInvitation: nil,
            payloadContainer: PayloadContainer(payloadType: .resetConversationV1, payload: ResetConversation())
        )
        
        let exp = expectation(description: "Envelope received")
        receiveCallback = { receivedEnvelope in
            XCTAssertEqual(receivedEnvelope.id, envelope.id)
            exp.fulfill()
        }
        
        webSocketReceiver.delegate = self
        
        let envelopeString = try JSONEncoder().encode(envelope).utf8String
        webSocketReceiver.websocketDidReceiveMessage(socket: MockWebSocketClient(), text: envelopeString)
        
        wait(for: [exp])
    }
    
    func testReceiveData() throws {
        let envelope = Envelope(
            id: MessageId(),
            senderId: UserId(),
            senderServerSignedMembershipCertificate: nil,
            receiverServerSignedMembershipCertificate: nil,
            timestamp: Date(),
            serverTimestamp: Date(),
            collapseId: nil,
            conversationInvitation: nil,
            payloadContainer: PayloadContainer(payloadType: .resetConversationV1, payload: ResetConversation())
        )
        
        let exp = expectation(description: "Envelope received")
        receiveCallback = { receivedEnvelope in
            XCTAssertEqual(receivedEnvelope.id, envelope.id)
            exp.fulfill()
        }
        
        webSocketReceiver.delegate = self
        
        let envelopeData = try JSONEncoder().encode(envelope)
        webSocketReceiver.websocketDidReceiveData(socket: MockWebSocketClient(), data: envelopeData)
        
        wait(for: [exp])
    }
}

extension WebSocketReceiverTests: EnvelopeReceiverDelegate {
    func receive(envelope: Envelope) {
        receiveCallback?(envelope)
    }
    
    func receive(envelope: Envelope, timeout: TimeInterval?, completionHandler: ((ReceiveEnvelopeResult) -> Void)?) {
    }
}

fileprivate class MockWebSocketClient: WebSocketClient {
    var delegate: WebSocketDelegate?
    var pongDelegate: WebSocketPongDelegate?
    var disableSSLCertValidation: Bool = false
    var overrideTrustHostname: Bool = false
    var desiredTrustHostname: String?
    var sslClientCertificate: SSLClientCertificate?
    var security: SSLTrustValidator?
    var enabledSSLCipherSuites: [SSLCipherSuite]?
    var isConnected: Bool = false
    
    func connect() { }
    func disconnect(forceTimeout: TimeInterval?, closeCode: UInt16) { }
    func write(string: String, completion: (() -> ())?) { }
    func write(data: Data, completion: (() -> ())?) { }
    func write(ping: Data, completion: (() -> ())?) { }
    func write(pong: Data, completion: (() -> ())?) { }
}
