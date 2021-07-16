//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import PromiseKit
import TICEAPIModels
import Chatto
import ChattoAdditions

class ChatManager: ChatManagerType {
    let userManager: UserManagerType
    let teamManager: TeamManagerType
    let groupManager: GroupManagerType
    let storageManager: ChatStorageManagerType
    let notifier: Notifier
    let nameSupplier: NameSupplierType
    let notificationManager: NotificationManagerType

    init(userManager: UserManagerType, teamManager: TeamManagerType, groupManager: GroupManagerType, signedInUser: SignedInUser, storageManager: ChatStorageManagerType, notifier: Notifier, nameSupplier: NameSupplierType, notificationManager: NotificationManagerType) {
        self.userManager = userManager
        self.teamManager = teamManager
        self.groupManager = groupManager
        self.storageManager = storageManager
        self.notifier = notifier
        self.nameSupplier = nameSupplier
        self.notificationManager = notificationManager
    }
    
    func lastMessage(for groupId: GroupId) -> ChatItemProtocol? {
        do {
            return try storageManager.lastMessage(for: groupId)
        } catch {
            logger.error("Failed to read last chat message: \(String(describing: error))")
            return nil
        }
    }

    func send(message: TextMessage, to team: Team) -> Promise<Void> {
        logger.debug("Sending message \(message.uid)")

        let payload = ChatMessage(groupId: team.groupId, text: message.text, imageData: nil)
        let payloadContainer = PayloadContainer(payloadType: .chatMessageV1, payload: payload)

        return groupManager.send(payloadContainer: payloadContainer, to: team, collapseId: nil, priority: .alert)
    }
    
    func add(message: ChatItemProtocol, to teamId: GroupId) {
        appendToHistory(message: message, groupId: teamId)
    }

    func appendToHistory(message: ChatItemProtocol, groupId: GroupId) {
        storageManager.save(messages: [message], for: groupId)
    }

    func updateStatus(updatedMessages: [ChatItemProtocol], groupId: GroupId) {
        let newMessages = updatedMessages.compactMap { updatedMessage -> ChatItemProtocol? in
            guard let message = try? storageManager.message(messageId: updatedMessage.uid) else {
                logger.error("Did not find message to update status for.")
                return nil
            }
            
            if let message = message as? MessageProtocol, let updatedMessage = updatedMessage as? MessageProtocol {
                message.status = updatedMessage.status
            }
            
            if let message = message as? ReadableMessageProtocol, let updatedMessage = updatedMessage as? ReadableMessageProtocol {
                message.read = updatedMessage.read
            }
            
            return message
        }
        
        storageManager.save(messages: newMessages, for: groupId)
        notificationManager.updateApplicationBadge(count: unreadMessageCount())
    }
    
    func unreadMessageCount() -> Int {
        do {
            return try storageManager.unreadMessageCount()
        } catch {
            logger.error("Could not get unread message count. Reason: \(error)")
            return 0
        }
    }
    
    func unreadMessages(groupId: GroupId) -> [ChatItemProtocol] {
        do {
            return try storageManager.unreadMessages(groupId: groupId)
        } catch {
            logger.error("Could not fetch unread messages. Reason: \(error)")
            return []
        }
    }
    
    func markAsRead(messageId: String, groupId: GroupId) {
        do {
            guard let message = try storageManager.message(messageId: messageId) as? ReadableMessageProtocol else { return }
            message.read = true
            updateStatus(updatedMessages: [message], groupId: groupId)
        } catch {
            logger.error("Could not mark message \(messageId) in group \(groupId) as read. Reason: \(error)")
        }
    }
    
    func markAllAsRead(groupId: GroupId) {
        do {
            let unreadMessages = try storageManager.unreadMessages(groupId: groupId)
            let readMessages = unreadMessages.compactMap { chatItem -> ChatItemProtocol? in
                let message = chatItem as? ReadableMessageProtocol
                message?.read = true
                return message
            }
            updateStatus(updatedMessages: readMessages, groupId: groupId)
        } catch {
            logger.error("Could not mark all as read for group \(groupId). Reason: \(error)")
        }
    }
}
