//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels
import GRDB

class ConversationStorageManager: ConversationStorageManagerType {

    enum SharedUserDefaultsKeys: String {
        case outboundConversationInvitations
        case inboundConversationInvitations
        case invalidConversations
    }

    let database: DatabaseWriter

    init(database: DatabaseWriter) {
        self.database = database
    }

    func storeOutboundConversationInvitation(receiverId: UserId, conversationId: ConversationId, conversationInvitation: ConversationInvitation) throws {
        let outboundConversationInvitation = OutboundConversationInvitation(receiverId: receiverId, conversationId: conversationId, conversationInvitation: conversationInvitation)

        try database.write { db in
            try outboundConversationInvitation.save(db)
        }
    }

    func outboundConversationInvitation(receiverId: UserId, conversationId: ConversationId) throws -> ConversationInvitation? {
        try database.read { db in
            try OutboundConversationInvitation.fetchOne(db, key: ["receiverId": receiverId, "conversationId": conversationId])?.conversationInvitation
        }
    }

    func deleteOutboundConversationInvitation(receiverId: UserId, conversationId: ConversationId) throws {
        return try database.write { db in
            try OutboundConversationInvitation.deleteOne(db, key: ["receiverId": receiverId, "conversationId": conversationId])
        }
    }

    func storeInboundConversationInvitation(senderId: UserId, conversationId: ConversationId, conversationInvitation: ConversationInvitation, timestamp: Date) throws {
        let inboundConversationInvitation = InboundConversationInvitation(senderId: senderId, conversationId: conversationId, timestamp: timestamp, conversationInvitation: conversationInvitation)

        try database.write { db in
            try inboundConversationInvitation.save(db)
        }
    }

    func inboundConversationInvitation(senderId: UserId, conversationId: ConversationId) throws -> InboundConversationInvitation? {
        try database.read { db in
            try InboundConversationInvitation.fetchOne(db, key: ["senderId": senderId, "conversationId": conversationId])
        }
    }
    
    func storeReceivedReset(senderId: UserId, conversationId: ConversationId, timestamp: Date) throws {
        try database.write { try ReceivedReset(senderId: senderId, conversationId: conversationId, timestamp: timestamp).save($0) }
    }
    
    func receivedReset(senderId: UserId, conversationId: ConversationId) throws -> Date? {
        try database.read { db in
            try ReceivedReset
                .select(Column("timestamp"), as: Date.self)
                .filter(key: ["senderId": senderId, "conversationId": conversationId])
                .fetchOne(db)
        }
    }

    func storeInvalidConversation(userId: UserId, conversationId: ConversationId, fingerprint: ConversationFingerprint, timestamp: Date, resendResetTimeout: Date) throws {
        let invalidConversation = InvalidConversation(senderId: userId, conversationId: conversationId, conversationFingerprint: fingerprint, timestamp: timestamp, resendResetTimeout: resendResetTimeout)

        try database.write { db in
            try invalidConversation.save(db)
        }
    }

    func invalidConversation(userId: UserId, conversationId: ConversationId) throws -> InvalidConversation? {
        try database.read { db in
            try InvalidConversation.fetchOne(db, key: ["senderId": userId, "conversationId": conversationId])
        }
    }

    func updateInvalidConversation(userId: UserId, conversationId: ConversationId, resendResetTimeout: Date) throws {
        try database.write { db in
            guard var oldInvalidConversation = try InvalidConversation.fetchOne(db, key: ["senderId": userId, "conversationId": conversationId]) else {
                logger.error("Could not update invalid conversation because it hasn't been found in the database.")
                return
            }
            try oldInvalidConversation.updateChanges(db) { $0.resendResetTimeout = resendResetTimeout }
        }
    }
}

extension ConversationStorageManager: DeletableStorageManagerType {
    func deleteAllData() {
        do {
            try database.write {
                try $0.drop(table: InboundConversationInvitation.databaseTableName)
                try $0.drop(table: OutboundConversationInvitation.databaseTableName)
                try $0.drop(table: InvalidConversation.databaseTableName)
            }
        } catch {
            logger.error("Error during deletion of all conversation data: \(String(describing: error))")
        }
    }
}

protocol ConversationInvitationRecord: Codable, PersistableRecord, FetchableRecord {
    var identityKey: PublicKey { get }
    var ephemeralKey: PublicKey { get }
    var usedOneTimePrekey: PublicKey? { get }

    var conversationInvitation: ConversationInvitation { get }
}

extension ConversationInvitationRecord {
    var conversationInvitation: ConversationInvitation {
        ConversationInvitation(identityKey: identityKey, ephemeralKey: ephemeralKey, usedOneTimePrekey: usedOneTimePrekey)
    }
}

struct InboundConversationInvitation: ConversationInvitationRecord {
    let senderId: UserId
    let conversationId: ConversationId
    let identityKey: PublicKey
    let ephemeralKey: PublicKey
    let usedOneTimePrekey: PublicKey?
    let timestamp: Date

    init(senderId: UserId, conversationId: ConversationId, timestamp: Date, conversationInvitation: ConversationInvitation) {
        self.senderId = senderId
        self.conversationId = conversationId
        self.timestamp = timestamp
        self.identityKey = conversationInvitation.identityKey
        self.ephemeralKey = conversationInvitation.ephemeralKey
        self.usedOneTimePrekey = conversationInvitation.usedOneTimePrekey
    }
}

struct OutboundConversationInvitation: ConversationInvitationRecord {
    let receiverId: UserId
    let conversationId: ConversationId
    let identityKey: PublicKey
    let ephemeralKey: PublicKey
    let usedOneTimePrekey: PublicKey?

    init(receiverId: UserId, conversationId: ConversationId, conversationInvitation: ConversationInvitation) {
        self.receiverId = receiverId
        self.conversationId = conversationId
        self.identityKey = conversationInvitation.identityKey
        self.ephemeralKey = conversationInvitation.ephemeralKey
        self.usedOneTimePrekey = conversationInvitation.usedOneTimePrekey
    }
}

struct ReceivedReset: Codable, PersistableRecord, FetchableRecord {
    let senderId: UserId
    let conversationId: ConversationId
    let timestamp: Date
}

struct InvalidConversation: Codable, PersistableRecord, FetchableRecord {
    let senderId: UserId
    let conversationId: ConversationId
    let conversationFingerprint: ConversationFingerprint
    let timestamp: Date
    var resendResetTimeout: Date
}
