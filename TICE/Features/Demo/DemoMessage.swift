//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import Chatto
import ChattoAdditions

typealias DemoMessage = DemoMessageModel<MessageModel>

public protocol DemoMessageModelProtocol: DecoratedMessageModelProtocol, ContentEquatableChatItemProtocol {
    var sender: DemoUser { get }
    var text: String { get }
}

open class DemoMessageModel<MessageModelT: MessageModelProtocol>: TextMessageModelProtocol {
    public var messageModel: MessageModelProtocol {
        return self._messageModel
    }
    public let _messageModel: MessageModelT // Can't make messasgeModel: MessageModelT: https://gist.github.com/diegosanchezr/5a66c7af862e1117b556
    public let sender: DemoUser
    public let text: String
    public init(sender: DemoUser, text: String, read: Bool = false) {
        // swiftlint:disable:next force_cast
        self._messageModel = MessageModel(uid: UUID().uuidString, senderId: sender.userId.uuidString, type: ChatComponent.text.rawValue, isIncoming: true, date: Date(), status: .success, read: read) as! MessageModelT
        self.sender = sender
        self.text = text
    }
    public func hasSameContent(as anotherItem: ChatItemProtocol) -> Bool {
        guard let anotherMessageModel = anotherItem as? DemoMessageModel else { return false }
        return self.text == anotherMessageModel.text
    }
}

extension DemoMessageModel: ReadableMessageProtocol where MessageModelT == MessageModel {
    public var read: Bool {
        get { self._messageModel.read }
        set { self._messageModel.read = newValue }
    }
}
