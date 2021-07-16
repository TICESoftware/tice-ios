//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import GRDB
import protocol DoubleRatchet.MessageKeyCache
import typealias DoubleRatchet.MessageKey
import typealias DoubleRatchet.PublicKey

struct MessageKeyCacheEntry: Codable, PersistableRecord, TableRecord, FetchableRecord {
    let conversationId: ConversationId
    let messageKey: MessageKey
    let messageNumber: Int
    let publicKey: Data
    let timestamp: Date
}

class DatabaseMessageKeyCache: MessageKeyCache {
    
    let conversationId: ConversationId
    let database: DatabaseWriter
    
    init(conversationId: ConversationId, database: DatabaseWriter) {
        self.conversationId = conversationId
        self.database = database
    }
    
    func add(messageKey: MessageKey, messageNumber: Int, publicKey: DoubleRatchet.PublicKey) throws {
        try database.write { db in
            let publicKeyData = Data(publicKey)
            let entry = MessageKeyCacheEntry(conversationId: conversationId, messageKey: messageKey, messageNumber: messageNumber, publicKey: publicKeyData, timestamp: Date())
            try entry.save(db)
        }
    }
    func getMessageKey(messageNumber: Int, publicKey: DoubleRatchet.PublicKey) throws -> MessageKey? {
        try database.read { db in
            let publicKeyData = Data(publicKey)
            let entry = try MessageKeyCacheEntry.fetchOne(db, key: ["conversationId": conversationId, "messageNumber": messageNumber, "publicKey": publicKeyData])
            return entry?.messageKey
        }
    }
    func remove(publicKey: DoubleRatchet.PublicKey, messageNumber: Int) throws {
        return try database.write { db in
            let publicKeyData = Data(publicKey)
            try MessageKeyCacheEntry.deleteOne(db, key: ["conversationId": conversationId, "messageNumber": messageNumber, "publicKey": publicKeyData])
        }
    }
}
