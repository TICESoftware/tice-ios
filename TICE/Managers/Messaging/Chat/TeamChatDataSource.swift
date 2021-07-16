//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import Chatto
import ChattoAdditions
import PromiseKit

protocol TeamChatDataSourceType: ChatDataSourceProtocol {
    func send(text: String)
}

class TeamChatDataSource: TeamChatDataSourceType {

    let team: Team
    let chatStorageManager: ChatStorageManagerType
    let chatManager: ChatManagerType
    let signedInUser: SignedInUser
    let messageSender: MessageSenderType
    let notifier: Notifier
    let loadLimit: Int
    
    var windowSize: Int
    var windowAnchor: Int

    weak var delegate: ChatDataSourceDelegateProtocol?
    
    private var messageObserverToken: ObserverToken?

    var chatItems: [ChatItemProtocol] {
        do {
            return try chatStorageManager.messages(for: team.groupId, offset: windowAnchor, limit: windowSize)
        } catch {
            logger.error("Could not load chat messages for updating chat slice. Reason: \(error)")
            return []
        }
    }

    var hasMoreNext: Bool {
        let messageCount = (try? chatStorageManager.messageCount(for: team.groupId)) ?? 0
        return windowAnchor + windowSize < messageCount
    }
    var hasMorePrevious: Bool { windowAnchor > 0 }
    
    private var foregroundTransitionObserverToken: NSObjectProtocol?

    init(team: Team, chatStorageManager: ChatStorageManagerType, chatManager: ChatManagerType, signedInUser: SignedInUser, messageSender: MessageSenderType, notifier: Notifier, loadLimit: Int) {
        self.team = team
        self.chatStorageManager = chatStorageManager
        self.chatManager = chatManager
        self.signedInUser = signedInUser
        self.messageSender = messageSender
        self.notifier = notifier
        self.loadLimit = loadLimit
        self.windowSize = loadLimit

        let messageCount = (try? chatStorageManager.messageCount(for: team.groupId)) ?? 0
        self.windowAnchor = max(0, messageCount - windowSize)

        messageObserverToken = chatStorageManager.observeMessagesCount(groupId: team.groupId, queue: .global()) { [unowned self] in
            self.resizeWindow(count: $0)
        }
        
        foregroundTransitionObserverToken = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil) { [unowned self] _ in self.handleForegroundTransition() }
    }

    deinit {
        messageObserverToken = nil
        
        foregroundTransitionObserverToken.map { NotificationCenter.default.removeObserver($0) }
    }
    
    private func resizeWindow(count: Int) {
        windowSize = min(count - windowAnchor, windowSize + loadLimit)
        DispatchQueue.main.async {
            self.delegate?.chatDataSourceDidUpdate(self, updateType: .normal)
        }
    }

    func loadNext() {
        do {
            let count = try chatStorageManager.messageCount(for: team.groupId)
            windowSize = min(count - windowAnchor, windowSize + loadLimit)
            delegate?.chatDataSourceDidUpdate(self, updateType: .pagination)
        } catch {
            logger.error("Could not load previos messages")
        }
    }

    func loadPrevious() {
        do {
            let count = try chatStorageManager.messageCount(for: team.groupId)
            windowAnchor = max(0, windowAnchor - loadLimit)
            windowSize = min(count, windowSize + loadLimit)
            delegate?.chatDataSourceDidUpdate(self, updateType: .pagination)
        } catch {
            logger.error("Could not load previos messages")
        }
    }

    func adjustNumberOfMessages(preferredMaxCount: Int?, focusPosition: Double, completion: (Bool) -> Void) {
        print(preferredMaxCount ?? 0)
    }

    func send(text: String) {
        firstly {
            messageSender.send(text: text, team: team)
        }.done { updateType in
            if let updateType = updateType {
                self.delegate?.chatDataSourceDidUpdate(self, updateType: updateType)
            }
        }.catch { error in
            logger.error("Could not send text message. Reason: \(error)")
        }
    }
    
    @objc
    private func handleForegroundTransition() {
        do {
            resizeWindow(count: try chatStorageManager.messageCount(for: team.groupId))
        } catch {
            logger.error("Error reloading data after transition to foreground: \(error)")
        }
    }
}
