//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import Chatto
import ChattoAdditions

typealias TextMessage = TextMessageModel<MessageModel>
typealias PhotoMessage = PhotoMessageModel<MessageModel>

open class MessageModel: MessageModelProtocol {
    open var uid: String
    open var senderId: String
    open var type: String
    open var isIncoming: Bool
    open var date: Date
    open var status: MessageStatus
    open var read: Bool

    public init(uid: String, senderId: String, type: String, isIncoming: Bool, date: Date, status: MessageStatus, read: Bool) {
        self.uid = uid
        self.senderId = senderId
        self.type = type
        self.isIncoming = isIncoming
        self.date = date
        self.status = status
        self.read = read
    }
}

extension TextMessageModel: MessageProtocol where MessageModelT == MessageModel {
    public var status: MessageStatus {
        get { self._messageModel.status }
        set { self._messageModel.status = newValue }
    }
}

extension TextMessageModel: ReadableMessageProtocol where MessageModelT == MessageModel {
    public var read: Bool {
        get { self._messageModel.read }
        set { self._messageModel.read = newValue }
    }
}

extension TextMessageModel: DateableProtocol {}

extension PhotoMessageModel: MessageProtocol where MessageModelT == MessageModel {
    public var status: MessageStatus {
        get { self._messageModel.status }
        set { self._messageModel.status = newValue }
    }
}

extension PhotoMessageModel: ReadableMessageProtocol where MessageModelT == MessageModel {
    public var read: Bool {
        get { self._messageModel.read }
        set { self._messageModel.read = newValue }
    }
}

extension PhotoMessageModel: DateableProtocol {}

public protocol DateableProtocol: ChatItemProtocol {
    var date: Date { get }
}

public protocol MessageProtocol: DecoratedMessageModelProtocol {
    var status: MessageStatus { get set }
}

public protocol ReadableMessageProtocol: ChatItemProtocol {
    var read: Bool { get set }
}

enum ChatComponent: String, Codable {
    case text
    case photo
    case sendingStatus
    case timeSeparator
    case meta
}
