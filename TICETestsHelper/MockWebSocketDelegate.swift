//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//

import Foundation
import Starscream

class MockWebSocketDelegate: WebSocketDelegate {
    
    var didConnect: (() -> Void)?
    var didDisconnect: ((Error?) -> Void)?
    var didReceiveMessage: ((String) -> Void)?
    var didReceiveData: ((Data) -> Void)?
    
    func websocketDidConnect(socket: WebSocketClient) {
        didConnect?()
    }
    
    func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
        didDisconnect?(error)
    }
    
    func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        didReceiveMessage?(text)
    }
    
    func websocketDidReceiveData(socket: WebSocketClient, data: Data) {
        didReceiveData?(data)
    }
}
