//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import PromiseKit
import Chatto
import ChattoAdditions

protocol MessageSenderType: AnyObject {
    func send(text: String, team: Team) -> Promise<UpdateType?>
}

class MessageSender: MessageSenderType {
    
    let chatManager: ChatManagerType
    let signedInUser: SignedInUser
    
    init(chatManager: ChatManagerType, signedInUser: SignedInUser) {
        self.chatManager = chatManager
        self.signedInUser = signedInUser
    }
    
    func send(text: String, team: Team) -> Promise<UpdateType?> {
        let uid = UUID().uuidString
        let senderId = signedInUser.userId.uuidString
        let type = ChatComponent.text.rawValue

        let messageModel = MessageModel(uid: uid, senderId: senderId, type: type, isIncoming: false, date: Date(), status: .sending, read: true)
        let message = TextMessage(messageModel: messageModel, text: text)

        chatManager.add(message: message, to: team.groupId)

        return firstly {
            chatManager.send(message: message, to: team)
        }.map {
            self.update(message: message, team: team, status: .success)
        }.recover { error -> Promise<UpdateType?> in
            logger.error("Failed to send chat message with error \(String(describing: error))")
            return .value(self.update(message: message, team: team, status: .failed))
        }
    }

    private func update(message: MessageProtocol, team: Team, status: MessageStatus) -> UpdateType? {
        guard message.status != status else { return nil }
        message.status = status
        chatManager.updateStatus(updatedMessages: [message], groupId: team.groupId)
        return .reload
    }
}
