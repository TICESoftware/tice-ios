//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels
import UIKit

class ChatMessageReceiver: ChatMessageReceiverType {
    
    weak var postOffice: PostOfficeType?
    let notificationManager: NotificationManagerType
    let userManager: UserManagerType
    let teamManager: TeamManagerType
    let chatManager: ChatManagerType
    let nameSupplier: NameSupplierType
    
    init(postOffice: PostOfficeType, notificationManager: NotificationManagerType, userManager: UserManagerType, teamManager: TeamManagerType, chatManager: ChatManagerType, nameSupplier: NameSupplierType) {
        self.postOffice = postOffice
        self.notificationManager = notificationManager
        self.userManager = userManager
        self.teamManager = teamManager
        self.chatManager = chatManager
        self.nameSupplier = nameSupplier
    }
    
    func registerHandler() {
        postOffice?.handlers[.chatMessageV1] = { [unowned self] in
            handleChatMessage(payload: $0, metaInfo: $1, completion: $2)
        }
    }
    
    deinit {
        postOffice?.handlers[.chatMessageV1] = nil
    }
    
    func handleChatMessage(payload: Payload, metaInfo: PayloadMetaInfo, completion: PostOfficeType.PayloadHandler?) {
        guard let chatMessage = payload as? ChatMessage else {
            logger.error("Invalid payload type. Expected chat message")
            completion?(.failed)
            return
        }
        
        if let text = chatMessage.text {
            let messageModel = MessageModel(uid: UUID().uuidString, senderId: metaInfo.senderId.uuidString, type: ChatComponent.text.rawValue, isIncoming: true, date: metaInfo.timestamp, status: .success, read: false)
            let textMessage = TextMessage(messageModel: messageModel, text: text)
            chatManager.add(message: textMessage, to: chatMessage.groupId)
            
            let user = userManager.user(metaInfo.senderId)
            let team = teamManager.teamWith(groupId: chatMessage.groupId)
            
            let notificationTitle: String
            switch (user, team) {
            case let (.some(user), .some(team)):
                notificationTitle = L10n.Notification.Group.Message.title(self.nameSupplier.name(user: user), nameSupplier.name(team: team))
            case let (.some(user), _):
                notificationTitle = L10n.Notification.Group.Message.Title.unknownGroup(nameSupplier.name(user: user))
            case let (_, .some(team)):
                notificationTitle = L10n.Notification.Group.Message.Title.unknownSender(nameSupplier.name(team: team))
            default:
                notificationTitle = L10n.Notification.Group.Message.Title.unknown
            }
            
            let notificationBody = L10n.Notification.Group.Message.Text.body(text)
            let userInfo = ["teamId": chatMessage.groupId.uuidString, "messageId": messageModel.uid]
            notificationManager.triggerNotification(title: notificationTitle, body: notificationBody, state: .main(.chat(team: chatMessage.groupId)), category: .messageReceived, userInfo: userInfo)
            updateApplicationBadge()
            completion?(.newData)
            return
        }
        
        if let imageData = chatMessage.imageData,
           let image = UIImage(data: imageData) {
            let messageModel = MessageModel(uid: UUID().uuidString, senderId: metaInfo.senderId.uuidString, type: ChatComponent.photo.rawValue, isIncoming: true, date: metaInfo.timestamp, status: .success, read: false)
            let photoMessage = PhotoMessage(messageModel: messageModel, imageSize: image.size, image: image)
            chatManager.add(message: photoMessage, to: chatMessage.groupId)
            
            let user = userManager.user(metaInfo.senderId)
            let team = teamManager.teamWith(groupId: chatMessage.groupId)
            
            let notificationTitle: String
            switch (user, team) {
            case let (.some(user), .some(team)):
                notificationTitle = L10n.Notification.Group.Message.title(nameSupplier.name(user: user), nameSupplier.name(team: team))
            case let (.some(user), _):
                notificationTitle = L10n.Notification.Group.Message.Title.unknownGroup(nameSupplier.name(user: user))
            case let (_, .some(team)):
                notificationTitle = L10n.Notification.Group.Message.Title.unknownSender(nameSupplier.name(team: team))
            default:
                notificationTitle = L10n.Notification.Group.Message.Title.unknown
            }
            
            let notificationBody = L10n.Notification.Group.Message.Photo.body
            let userInfo = ["teamId": chatMessage.groupId.uuidString, "messageId": messageModel.uid]
            notificationManager.triggerNotification(title: notificationTitle, body: notificationBody, state: .main(.chat(team: chatMessage.groupId)), category: .messageReceived, userInfo: userInfo)
            updateApplicationBadge()
            completion?(.newData)
            return
        }
        
        logger.error("Unsupported message content.")
        completion?(.failed)
    }
    
    private func updateApplicationBadge() {
        let unreadMessageCount = chatManager.unreadMessageCount()
        notificationManager.updateApplicationBadge(count: unreadMessageCount)
    }
}
