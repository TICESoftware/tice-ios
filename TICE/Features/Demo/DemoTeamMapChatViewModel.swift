//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import Observable

class DemoTeamMapChatViewModel: TeamMapChatViewModelType {
    
    let demoManager: DemoManagerType
    let notifier: Notifier
    
    let coordinator: DemoFlow
    
    var chatBadgeNumber: MutableObservable<Int>
    var lastMessage: MutableObservable<LastMessage?>
    
    init(demoManager: DemoManagerType, notifier: Notifier, coordinator: DemoFlow) {
        self.demoManager = demoManager
        self.notifier = notifier
        
        self.coordinator = coordinator
        
        self.chatBadgeNumber = MutableObservable(0)
        self.lastMessage = MutableObservable(nil)
        
        notifier.register(DemoMessageNotificationHandler.self, observer: self)
    }
    
    deinit {
        notifier.unregister(DemoMessageNotificationHandler.self, observer: self)
    }
    
    func didTapChatBar() {
        coordinator.showChat()
    }
}

extension DemoTeamMapChatViewModel: DemoMessageNotificationHandler {
    func didReceive(message: DemoMessage) {
        guard !message.read else { return }
        let avatar = demoManager.avatar(demoUser: message.sender)
        self.lastMessage.wrappedValue = LastMessage(message: message.text,
                                             avatar: avatar,
                                             timestamp: message.date,
                                             chatItem: message)
    }
    
    func didRead(message: DemoMessage) {
        if message === lastMessage.wrappedValue?.chatItem {
            lastMessage.wrappedValue = nil
        }
    }
}
