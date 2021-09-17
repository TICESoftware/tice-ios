//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels
import Starscream

class WebSocketReceiver: Receiver {
    
    weak var delegate: EnvelopeReceiverDelegate?
    var socket: WebSocketType
    
    private let signedInUserManager: SignedInUserManagerType
    private let authManager: AuthManagerType
    private let notifier: Notifier
    private let decoder: JSONDecoder
    private var shouldConnect: Bool = false
    
    private let defaultReconnectTime: TimeInterval
    private var nextReconnectTime: TimeInterval
    private var reconnectTimer: Timer?
    
    // ws://
    init(webSocket: WebSocketType, signedInUserManager: SignedInUserManagerType, authManager: AuthManagerType, decoder: JSONDecoder, notifier: Notifier, reconnectTime: TimeInterval) {
        self.socket = webSocket
        self.decoder = decoder
        self.signedInUserManager = signedInUserManager
        self.authManager = authManager
        self.notifier = notifier
        self.defaultReconnectTime = reconnectTime
        self.nextReconnectTime = reconnectTime
        
        socket.delegate = self
        
        notifier.register(SignedInUserNotificationHandler.self, observer: self)
    }
    
    deinit {
        notifier.unregister(SignedInUserNotificationHandler.self, observer: self)
    }
    
    func connect() {
        guard !socket.isConnected else { return }
        shouldConnect = true
        
        logger.info("Connecting WebSocket")
        
        guard let signedInUser = signedInUserManager.signedInUser else {
            logger.info("Aborting to connect to WebSocket. Reason: User is not signed in")
            return
        }
        
        let authorization: Certificate
        do {
            authorization = try authManager.generateAuthHeader(signingKey: signedInUser.privateSigningKey, userId: signedInUser.userId)
        } catch {
            logger.warning("Could not generate auth header for WebSocket. Reason: \(error)")
            return
        }
        
        socket.request.setValue(authorization, forHTTPHeaderField: "X-Authorization")
        socket.connect()
    }
    
    func disconnect() {
        socket.disconnect()
        shouldConnect = false
    }
    
    private func reconnect() {
        nextReconnectTime *= 2
        connect()
    }
}

extension WebSocketReceiver: SignedInUserNotificationHandler {
    func userDidSignIn(_ signedInUser: SignedInUser) {
        if socket.isConnected {
            disconnect()
            shouldConnect = true
        }
        
        if shouldConnect {
            connect()
        }
    }
    
    func userDidSignOut() {
        socket.request.setValue(nil, forHTTPHeaderField: "X-Authorization")
        disconnect()
    }
}

extension WebSocketReceiver: WebSocketDelegate {
    // Starscream capitalizes the official name "WebSocket" inconsistently as "websocket" in delegate calls.
    
    public func websocketDidConnect(socket: WebSocketClient) {
        logger.info("WebSocket \(socket) did connect.")
        
        nextReconnectTime = defaultReconnectTime
        reconnectTimer?.invalidate()
    }
    
    public func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
        if let error = error as? WSError, error.type == .protocolError && error.code == CloseCode.normal.rawValue {
            logger.info("WebSocket closed by server.")
        } else {
            logger.warning("WebSocket \(socket) did disconnect. Reason: \(String(describing: error))")
        }
        
        guard shouldConnect else {
            logger.info("Not trying to reconnect the WebSocket.")
            return
        }
        
        logger.info("Trying to reconnect the WebSocket in \(nextReconnectTime)s.")
        
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: nextReconnectTime, repeats: false) { [weak self] _ in
            self?.reconnect()
        }
    }
    
    public func websocketDidReceiveData(socket: WebSocketClient, data: Data) {
        guard let envelope = try? decoder.decode(Envelope.self, from: data) else {
            logger.warning("Received non envelope data over WebSocket. Data: \(data)")
            return
        }

        logger.debug("Received envelope \(envelope.id) from \(envelope.senderId) over WebSocket.")
        receive(envelope: envelope)
    }
    
    public func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        guard let data = text.data(using: .utf8) else {
            logger.warning("Received non string over WebSocket.")
            return
        }

        do {
            let envelope = try decoder.decode(Envelope.self, from: data)
            logger.debug("Received envelope \(envelope.id) from \(envelope.senderId) over WebSocket.")
            receive(envelope: envelope)
        } catch {
            logger.warning("Received non envelope over WebSocket. Reason: \(error)")
        }
    }
    
    public func websocketDidReceiveError(error: Error, data: Data) {
        logger.error("Receiving data \(data) over the WebSocket failed. Reason: \(error)")
    }
}
