//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import Observable
import Chatto

protocol TeamMapChatViewModelType {
    var chatBadgeNumber: MutableObservable<Int> { get }
    var lastMessage: MutableObservable<LastMessage?> { get }
    
    func didTapChatBar()
}

struct LastMessage {
    let message: String
    let avatar: UIImage?
    let timestamp: Date
    let chatItem: ReadableMessageProtocol
}

extension LastMessage: Equatable {
    static func == (lhs: LastMessage, rhs: LastMessage) -> Bool {
        return lhs.chatItem.uid == rhs.chatItem.uid
    }
}

class TeamMapChatViewModel: TeamMapChatViewModelType {
    
    let nameSupplier: NameSupplierType
    let chatStorageManager: ChatStorageManagerType
    let userManager: UserManagerType
    let avatarSupplier: AvatarSupplierType
    let notifier: Notifier
    let coordinator: MainFlow
    
    let team: Team
    
    let chatBadgeNumber: MutableObservable<Int>
    let lastMessage: MutableObservable<LastMessage?>
    
    private var lastMessages: [LastMessage] = []
    private var dispatchedTask: DispatchWorkItem?
    
    private var incomingMessageObserverToken: ObserverToken?
    private var unreadMessagesCountObserver: ObserverToken?
    
    private var foregroundTransitionObserverToken: NSObjectProtocol?
    
    init(nameSupplier: NameSupplierType, chatStorageManager: ChatStorageManagerType, userManager: UserManagerType, avatarSupplier: AvatarSupplierType, notifier: Notifier, coordinator: MainFlow, team: Team) {
        self.nameSupplier = nameSupplier
        self.chatStorageManager = chatStorageManager
        self.userManager = userManager
        self.avatarSupplier = avatarSupplier
        self.notifier = notifier
        self.coordinator = coordinator
        self.team = team
        
        chatBadgeNumber = MutableObservable(0)
        lastMessage = MutableObservable(nil)
        
        incomingMessageObserverToken = chatStorageManager.observeIncomingMessages(groupId: team.groupId, queue: .main) { [unowned self] lastUnreadMessage in
            guard let lastUnreadMessage = lastUnreadMessage else { return }
            self.didReceive(message: lastUnreadMessage)
        }
        
        unreadMessagesCountObserver = chatStorageManager.observeUnreadMessagesCount(groupId: team.groupId, queue: .main) { [unowned self] in
            self.chatBadgeNumber.wrappedValue = $0
            self.updateLastMessages()
        }
        
        foregroundTransitionObserverToken = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil) { [unowned self] _ in self.handleForegroundTransition() }
    }
    
    deinit {
        incomingMessageObserverToken = nil
        unreadMessagesCountObserver = nil
        
        foregroundTransitionObserverToken.map { NotificationCenter.default.removeObserver($0) }
    }
    
    func didTapChatBar() {
        coordinator.showChat(for: team, animated: true)
    }
    
    func didReceive(message: ChatItemProtocol) {
        guard let message = message as? TextMessage else { return }
        
        guard let userId = UUID(uuidString: message.senderId),
              let user = userManager.user(userId) else {
            return
        }
        let avatar = avatarSupplier.avatar(user: user, size: CGSize(width: 48, height: 48), rounded: true)
        add(lastMessage: LastMessage(message: message.text, avatar: avatar, timestamp: Date(), chatItem: message))
    }
    
    func add(lastMessage message: LastMessage) {
        lastMessages.append(message)
        if lastMessage.wrappedValue == nil {
            lastMessage.wrappedValue = message
            scheduleLastMessageUpdate(in: .seconds(4))
        }
    }
    
    func scheduleLastMessageUpdate(in timeInterval: DispatchTimeInterval) {
        dispatchedTask?.cancel()
        
        let task = DispatchWorkItem { [weak self] in
            self?.popLastMessage()
        }
        DispatchQueue.global().asyncAfter(wallDeadline: .now() + timeInterval, execute: task)
        dispatchedTask = task
    }
    
    func updateLastMessages() {
        lastMessages = lastMessages.filter {
            do {
                let message = try chatStorageManager.message(messageId: $0.chatItem.uid) as? ReadableMessageProtocol
                return message?.read == false
            } catch {
                return false
            }
        }
        
        guard let lastChatItem = lastMessages.first?.chatItem, !lastChatItem.read else {
            popLastMessage()
            return
        }
    }
    
    func popLastMessage() {
        dispatchedTask?.cancel()
        
        guard !lastMessages.isEmpty else {
            lastMessage.wrappedValue = nil
            return
        }
        lastMessages.remove(at: 0)
        lastMessages.removeAll { message -> Bool in
            return message.chatItem.read
        }
        
        let nextLastMessage = lastMessages.first
        lastMessage.wrappedValue = nextLastMessage
        
        if nextLastMessage != nil {
            scheduleLastMessageUpdate(in: .seconds(4))
        }
    }
    
    @objc
    private func handleForegroundTransition() {
        do {
            self.chatBadgeNumber.wrappedValue = try chatStorageManager.unreadMessageCount()
        } catch {
            logger.error("Error reloading data after transition to foreground: \(error)")
        }
    }
}
