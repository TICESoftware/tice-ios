//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import Chatto
import ChattoAdditions

class ChatViewController: BaseChatViewController {

    var viewModel: ChatViewModelType! {
        didSet {
            viewModel.delegate = self
        }
    }
    var chatInputView: ChatBar!

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = viewModel.title
        self.chatItemsDecorator = ChatItemsDecorator()
        self.inputContentContainer.backgroundColor = .highlightBackground
        self.view.backgroundColor = .background

        setChatDataSource(viewModel.chatDataSource, triggeringUpdateType: .firstLoad)
        
        DispatchQueue.main.async {
            self.chatInputView.inputTextView?.becomeFirstResponder()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    
        enqueueModelUpdate(updateType: .normal)
        viewModel.viewWillAppear()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        viewModel.viewDidDisappear()
    }

    var chatInputPresenter: BasicChatInputBarPresenter!

    override func createChatInputView() -> UIView {
        chatInputView = ChatBar.loadCustomNib()
        
        var appearance = ChatInputBarAppearance()
        appearance.textInputAppearance.placeholderFont = .systemFont(ofSize: 17)
        appearance.textInputAppearance.font = .systemFont(ofSize: 17)
        appearance.textInputAppearance.textInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        appearance.textInputAppearance.textColor = .label
        appearance.textInputAppearance.placeholderColor = .secondaryLabel
        appearance.tabBarAppearance.height = 0
        appearance.sendButtonAppearance.title = ""
        appearance.sendButtonAppearance.insets = .zero
        appearance.textInputAppearance.placeholderText = L10n.Chat.Bar.placeholder
        self.chatInputPresenter = BasicChatInputBarPresenter(chatInputBar: chatInputView, chatInputItems: self.createChatInputItems(), chatInputBarAppearance: appearance)
        chatInputView.maxCharactersCount = 1000
        chatInputView.isEnabled = viewModel.chatInputEnabled
        
        return chatInputView
    }

    func createChatInputItems() -> [ChatInputItemProtocol] {
        var items = [ChatInputItemProtocol]()
        items.append(self.createTextInputItem())
        return items
    }

    private func createTextInputItem() -> TextChatInputItem {
        let item = TextChatInputItem()
        item.textInputHandler = { [weak self] text in
            self?.viewModel.send(text: text)
        }
        return item
    }

    override func createPresenterBuilders() -> [ChatItemType: [ChatItemPresenterBuilderProtocol]] {
        return viewModel.createPresenterBuilders()
    }
    
    @IBAction func closeChat(_ sender: Any) {
        viewModel.close()
    }
}

protocol ChatViewModelType {
    var delegate: ChatViewController? { get set }
    
    var title: String { get }
    var chatDataSource: ChatDataSourceProtocol { get }
    var chatInputEnabled: Bool { get }
    
    func viewWillAppear()
    func viewDidDisappear()
    
    func send(text: String)
    func close()
    func createPresenterBuilders() -> [ChatItemType: [ChatItemPresenterBuilderProtocol]]
}

class ChatViewModel: ChatViewModelType {
    
    let team: Team
    let coordinator: MainFlow
    
    let chatManager: ChatManagerType
    let teamChatDataSource: TeamChatDataSourceType
    let chatStorageManager: ChatStorageManagerType
    let userManager: UserManagerType
    let avatarSupplier: AvatarSupplierType
    let nameSupplier: NameSupplierType
    
    weak var delegate: ChatViewController?

    var textMessageViewModelBuilder: TextMessageViewModelBuilder {
        TextMessageViewModelBuilder(userManager: userManager, avatarSupplier: avatarSupplier)
    }

    var photoMessageViewModelBuilder: PhotoMessageViewModelBuilder {
        PhotoMessageViewModelBuilder(userManager: userManager, avatarSupplier: avatarSupplier)
    }
    
    var chatDataSource: ChatDataSourceProtocol { teamChatDataSource }
    
    var chatInputEnabled: Bool = true
    
    private var foregroundTransitionObserverToken: NSObjectProtocol?
    private var incomingMessageObserverToken: ObserverToken?

    init(chatManager: ChatManagerType, teamChatDataSource: TeamChatDataSourceType, chatStorageManager: ChatStorageManagerType, userManager: UserManagerType, avatarSupplier: AvatarSupplierType, nameSupplier: NameSupplierType, coordinator: MainFlow, team: Team) {
        self.chatManager = chatManager
        self.teamChatDataSource = teamChatDataSource
        self.chatStorageManager = chatStorageManager
        self.userManager = userManager
        self.avatarSupplier = avatarSupplier
        self.nameSupplier = nameSupplier
        self.coordinator = coordinator
        self.team = team
    
        foregroundTransitionObserverToken = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil) { [unowned self] _ in self.applicationWillEnterForeground() }
        
        incomingMessageObserverToken = chatStorageManager.observeIncomingMessages(groupId: team.groupId, queue: .main) { [unowned self] in
            guard let readableMessage = $0 as? ReadableMessageProtocol else { return }
            readableMessage.read = true
            self.chatManager.updateStatus(updatedMessages: [readableMessage], groupId: team.groupId)
        }
    }
    
    deinit {
        foregroundTransitionObserverToken.map { NotificationCenter.default.removeObserver($0) }
        incomingMessageObserverToken = nil
    }
    
    var title: String {
        return L10n.Chat.title(nameSupplier.name(team: team))
    }
    
    func viewWillAppear() {
        chatManager.markAllAsRead(groupId: team.groupId)
    }
    
    func viewDidDisappear() {
        
    }

    func send(text: String) {
        guard !text.isEmpty else {
            logger.debug("Not sending empty text message.")
            return
        }
        teamChatDataSource.send(text: text)
    }
    
    func close() {
        coordinator.leaveChat()
    }
    
    func createPresenterBuilders() -> [ChatItemType: [ChatItemPresenterBuilderProtocol]] {
        let textMessagePresenter = TextMessagePresenterBuilder(
            viewModelBuilder: textMessageViewModelBuilder,
            interactionHandler: MessageInteractionHandler()
        )
        
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
    
    private func applicationWillEnterForeground() {
        delegate?.enqueueModelUpdate(updateType: .normal)
    }
}
