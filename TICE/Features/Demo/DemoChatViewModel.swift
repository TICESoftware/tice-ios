//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import Chatto
import ChattoAdditions

class DemoChatDataSource: ChatDataSourceProtocol {
    
    var demoManager: DemoManagerType
    
    init(demoManager: DemoManagerType) {
        self.demoManager = demoManager
    }
    
    var hasMoreNext: Bool = false
    
    var hasMorePrevious: Bool = false
    
    var chatItems: [ChatItemProtocol] { demoManager.messages }
    
    weak var delegate: ChatDataSourceDelegateProtocol?
    
    func loadNext() {
    }
    
    func loadPrevious() {
    }
    
    func adjustNumberOfMessages(preferredMaxCount: Int?, focusPosition: Double, completion: (Bool) -> Void) {
    }
    
}

class DemoTextMessageViewModelBuilder: ViewModelBuilderProtocol {
    
    let demoManager: DemoManagerType
    
    let messageViewModelBuilder = MessageViewModelDefaultBuilder()
    
    var team: DemoTeam { demoManager.demoTeam.wrappedValue }
    
    init(demoManager: DemoManagerType) {
        self.demoManager = demoManager
    }

    func createViewModel(_ model: DemoMessage) -> TextMessageViewModel {
        let messageViewModel = self.messageViewModelBuilder.createMessageViewModel(model)
        let textMessageViewModel = TextMessageViewModel(text: model.text, messageViewModel: messageViewModel)
        textMessageViewModel.avatarImage = .init(demoManager.avatar(demoUser: model.sender))
        return textMessageViewModel
    }

    public func canCreateViewModel(fromModel model: Any) -> Bool {
        return model is DemoMessage
    }
}

class DemoChatViewModel: ChatViewModelType {
    weak var delegate: ChatViewController?
    
    let demoManager: DemoManagerType
    let notifier: Notifier
    
    var coordinator: DemoFlow
    
    var team: DemoTeam { demoManager.demoTeam.wrappedValue }
    
    init(demoManager: DemoManagerType, notifier: Notifier, coordinator: DemoFlow) {
        self.demoManager = demoManager
        self.notifier = notifier
        self.coordinator = coordinator
        
        self.demoChatDataSource = DemoChatDataSource(demoManager: demoManager)
        self.textMessagePresenter = TextMessagePresenterBuilder(
            viewModelBuilder: DemoTextMessageViewModelBuilder(demoManager: demoManager),
            interactionHandler: MessageInteractionHandler()
        )
        
        notifier.register(DemoMessageNotificationHandler.self, observer: self)
    }
    
    deinit {
        notifier.unregister(DemoMessageNotificationHandler.self, observer: self)
    }
    
    var title: String {
        L10n.Chat.title(team.name)
    }
    
    var chatDataSource: ChatDataSourceProtocol { demoChatDataSource }
    
    var demoChatDataSource: DemoChatDataSource
    
    let textMessagePresenter: TextMessagePresenterBuilder<DemoTextMessageViewModelBuilder, MessageInteractionHandler<DemoMessage, TextMessageViewModel>>
    
    var chatInputEnabled: Bool = false
    
    func viewWillAppear() {
        demoManager.didOpenChat()
    }
    
    func viewDidDisappear() {
        demoManager.didCloseChat()
    }
    
    func send(text: String) {
        fatalError()
    }
    
    func close() {
        coordinator.leaveChat()
    }
    
    func createPresenterBuilders() -> [ChatItemType: [ChatItemPresenterBuilderProtocol]] {
        let colors = BaseMessageCollectionViewCellDefaultStyle.Colors(incoming: .secondarySystemFill,
                                                                      outgoing: UIColor.highlightBackground)
        
        let avatarStyle = BaseMessageCollectionViewCellDefaultStyle.AvatarStyle(size: CGSize(width: 32, height: 32), alignment: .bottom)
        let baseStyle = BaseMessageCollectionViewCellDefaultStyle(colors: colors,
                                                                  incomingAvatarStyle: avatarStyle)
        
        let textStyle = TextMessageCollectionViewCellDefaultStyle.TextStyle(
            font: UIFont.systemFont(ofSize: 16),
            incomingColor: .label,
            outgoingColor: UIColor.white,
            incomingInsets: UIEdgeInsets(top: 10, left: 19, bottom: 10, right: 15),
            outgoingInsets: UIEdgeInsets(top: 10, left: 15, bottom: 10, right: 19)
        )
        
        textMessagePresenter.textCellStyle = TextMessageCollectionViewCellDefaultStyle(textStyle: textStyle, baseStyle: baseStyle)
        textMessagePresenter.baseMessageStyle = baseStyle
        
        return [
            ChatComponent.text.rawValue: [textMessagePresenter],
            ChatComponent.sendingStatus.rawValue: [SendingStatusPresenterBuilder()],
            ChatComponent.timeSeparator.rawValue: [TimeSeparatorPresenterBuilder()],
            ChatComponent.meta.rawValue: [MetaMessagePresenterBuilder()]
        ]
    }
}

extension DemoChatViewModel: DemoMessageNotificationHandler {
    func didReceive(message: DemoMessage) {
        delegate?.chatDataSourceDidUpdate(demoChatDataSource, updateType: .normal)
    }
    
    func didRead(message: DemoMessage) {
        
    }
}
