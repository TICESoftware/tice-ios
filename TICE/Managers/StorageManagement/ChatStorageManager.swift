//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import Chatto
import ChattoAdditions
import GRDB

protocol ChatStorageManagerType: DeletableStorageManagerType {
    func unreadMessageCount() throws -> Int
    
    func save(messages: [ChatItemProtocol], for groupId: GroupId)
    func message(messageId: String) throws -> ChatItemProtocol?
    func messageCount(for groupId: GroupId) throws -> Int
    func messages(for groupId: GroupId, offset: Int?, limit: Int) throws -> [ChatItemProtocol]
    func lastMessage(for groupId: GroupId) throws -> ChatItemProtocol?
    func unreadMessages(groupId: GroupId) throws -> [ChatItemProtocol]
    
    func observeMessageUpdates(queue: DispatchQueue, onChange: @escaping () -> Void) -> ObserverToken
    func observeIncomingMessages(groupId: GroupId, queue: DispatchQueue, onChange: @escaping (ChatItemProtocol?) -> Void) -> ObserverToken
    func observeMessagesCount(groupId: GroupId, queue: DispatchQueue, onChange: @escaping (Int) -> Void) -> ObserverToken
    func observeUnreadMessagesCount(groupId: GroupId, queue: DispatchQueue, onChange: @escaping (Int) -> Void) -> ObserverToken
}

class ChatStorageManager: ChatStorageManagerType {
    
    let database: DatabaseWriter
    
    init(database: DatabaseWriter) {
        self.database = database
    }
    
    func save(messages: [ChatItemProtocol], for groupId: GroupId) {
        let rawMessages = messages.compactMap { message -> RawChatMessage? in
            switch message {
            case let message as TextMessage:
                return RawChatMessage(message: message, groupId: groupId)
            case let message as PhotoMessage:
                return RawChatMessage(message: message, groupId: groupId)
            case let message as MetaMessage:
                return RawChatMessage(message: message, groupId: groupId)
            default:
                logger.error("Invalid message type.")
                return nil
            }
        }

        do {
            try database.write { db in
                try rawMessages.forEach { try $0.save(db) }
            }
        } catch {
            logger.error("Failed to insert chat message record: \(String(describing: error))")
        }
    }
    
    func message(messageId: String) throws -> ChatItemProtocol? {
        try database.read { db -> ChatItemProtocol? in
            return try RawChatMessage.fetchOne(db, key: messageId)?.chatItem
        }
    }
    
    func unreadMessageCount() throws -> Int {
        try database.read { db in
            return try RawChatMessage.filter(Column("read") == false).fetchCount(db)
        }
    }
    
    func messageCount(for groupId: GroupId) throws -> Int {
        try database.read { db in
            return try RawChatMessage.filter(Column("groupId") == groupId).fetchCount(db)
        }
    }

    func messages(for groupId: GroupId, offset: Int?, limit: Int) throws -> [ChatItemProtocol] {
        try database.read { db -> [ChatItemProtocol] in
            let rawMessages: [RawChatMessage] = try RawChatMessage.filter(Column("groupId") == groupId).limit(limit, offset: offset).fetchAll(db)
            return rawMessages.compactMap { rawMessage in
                guard let chatItem = rawMessage.chatItem else {
                    logger.error("Invalid raw message.")
                    return nil
                }
                return chatItem
            }
        }
    }
    
    func lastMessage(for groupId: GroupId) throws -> ChatItemProtocol? {
        try database.read { db -> ChatItemProtocol? in
            let rawMessage = try RawChatMessage.filter(Column("groupId") == groupId).order(Column("date").desc).fetchOne(db)
            return rawMessage?.chatItem
        }
    }
    
    func unreadMessages(groupId: GroupId) throws -> [ChatItemProtocol] {
        try database.read { db in
            let rawMessages = try RawChatMessage.filter(Column("groupId") == groupId).filter(Column("read") == false).fetchAll(db)
            return rawMessages.compactMap { $0.chatItem }
        }
    }
    
    func observeMessageUpdates(queue: DispatchQueue, onChange: @escaping () -> Void) -> ObserverToken {
        database.observe(RawChatMessage.fetchAll, queue: queue, onChange: { _ in onChange() })
    }
    
    func observeIncomingMessages(groupId: GroupId, queue: DispatchQueue, onChange: @escaping (ChatItemProtocol?) -> Void) -> ObserverToken {
        let threshold = Date()
        return database.observe({ db in
            try RawChatMessage
                .filter(Column("groupId") == groupId)
                .filter(Column("read") == false)
                .filter(Column("date") > threshold)
                .order(Column("date").desc)
                .fetchOne(db)?
                .chatItem
        },
        queue: queue,
        onChange: onChange)
    }
    
    func observeMessagesCount(groupId: GroupId, queue: DispatchQueue, onChange: @escaping (Int) -> Void) -> ObserverToken {
        database.observe({ db in
            try RawChatMessage
                .filter(Column("groupId") == groupId)
                .fetchCount(db)
        },
        queue: queue,
        onChange: onChange)
    }
    
    func observeUnreadMessagesCount(groupId: GroupId, queue: DispatchQueue, onChange: @escaping (Int) -> Void) -> ObserverToken {
        database.observe({ db in
            try RawChatMessage
                .filter(Column("groupId") == groupId)
                .filter(Column("read") == false)
                .fetchCount(db)
        },
        queue: queue,
        onChange: onChange)
    }
}

extension ChatStorageManager: DeletableStorageManagerType {
    func deleteAllData() {
        do {
            try database.write { try $0.drop(table: RawChatMessage.databaseTableName) }
        } catch {
            logger.error("Error during deletion of all chat data: \(String(describing: error))")
        }
    }
}

struct RawChatMessage: Hashable, Codable, PersistableRecord, FetchableRecord, TableRecord {
    
    let groupId: GroupId
    
    let uid: String
    let type: RawType
    let date: Date
    let read: Bool
    
    let senderId: String?
    let isIncoming: Bool?
    let status: RawStatus?
    
    let text: String?
    let imageData: Data?

    init(message: TextMessage, groupId: GroupId) {
        self.groupId = groupId
        
        self.uid = message.uid
        self.senderId = message.senderId
        self.type = .text
        self.isIncoming = message.isIncoming
        self.date = message.date
        self.status = RawStatus(status: message.status)
        self.read = message.read
        self.text = message.text
        
        self.imageData = nil
    }

    init(message: PhotoMessage, groupId: GroupId) {
        self.groupId = groupId
        
        self.uid = message.uid
        self.senderId = message.senderId
        self.type = .photo
        self.isIncoming = message.isIncoming
        self.date = message.date
        self.status = RawStatus(status: message.status)
        self.read = message.read
        self.imageData = message.image.pngData()
        
        self.text = nil
    }
    
    init(message: MetaMessage, groupId: GroupId) {
        self.groupId = groupId
        
        self.type = .meta
        self.uid = message.uid
        self.date = message.date
        self.text = message.message
        self.read = message.read
        
        self.senderId = nil
        self.imageData = nil
        self.status = nil
        self.isIncoming = nil
    }

    var chatItem: ChatItemProtocol? {
        switch type {
        case .text:
            guard let text = text,
                let senderId = senderId,
                let isIncoming = isIncoming,
                let status = status else {
                    return nil
            }
            let messageModel = MessageModel(uid: uid, senderId: senderId, type: type.messageType, isIncoming: isIncoming, date: date, status: status.status, read: read)
            return TextMessage(messageModel: messageModel, text: text)
        case .photo:
            guard let imageData = imageData,
                let image = UIImage(data: imageData),
                let senderId = senderId,
                let isIncoming = isIncoming,
                let status = status else {
                    return nil
            }
            let messageModel = MessageModel(uid: uid, senderId: senderId, type: type.messageType, isIncoming: isIncoming, date: date, status: status.status, read: read)
            return PhotoMessage(messageModel: messageModel, imageSize: image.size, image: image)
        case .meta:
            guard let text = text else { return nil }
            return MetaMessage(uid: uid, date: date, message: text, read: read)
        }
    }

    enum RawType: String, Codable {
        case text
        case photo
        case meta

        var messageType: ChatItemType {
            switch self {
            case .text: return ChatComponent.text.rawValue
            case .photo: return ChatComponent.photo.rawValue
            case .meta: return ChatComponent.meta.rawValue
            }
        }
    }

    enum RawStatus: String, Codable {
        case sending
        case success
        case failed

        init(status: MessageStatus) {
            switch status {
            case .sending: self = .sending
            case .success: self = .success
            case .failed: self = .failed
            }
        }

        var status: MessageStatus {
            switch self {
            case .sending: return .sending
            case .success: return .success
            case .failed: return .failed
            }
        }
    }
}
