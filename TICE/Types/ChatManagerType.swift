//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import PromiseKit
import Chatto
import ChattoAdditions

protocol ChatManagerType {
    func lastMessage(for groupId: GroupId) -> ChatItemProtocol?
    
    func unreadMessageCount() -> Int
    func unreadMessages(groupId: GroupId) -> [ChatItemProtocol]

    func updateStatus(updatedMessages: [ChatItemProtocol], groupId: GroupId)
    func send(message: TextMessage, to team: Team) -> Promise<Void>
    func add(message: ChatItemProtocol, to teamId: GroupId)
    
    func markAsRead(messageId: String, groupId: GroupId)
    func markAllAsRead(groupId: GroupId)
}
