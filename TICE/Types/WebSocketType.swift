//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import Starscream

protocol WebSocketType {
    var delegate: WebSocketDelegate? { get set }
    var isConnected: Bool { get }
    var request: URLRequest { get set }
    
    func connect()
    func disconnect()
}

extension WebSocket: WebSocketType { }
