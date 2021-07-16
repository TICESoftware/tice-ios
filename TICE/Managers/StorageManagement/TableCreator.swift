//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import GRDB

protocol TableCreatorType {
    func createTablesIfNecessary(database: DatabaseWriter) throws
}

class TableCreator: TableCreatorType {
    func createTablesIfNecessary(database: DatabaseWriter) throws {
        try database.write { db in
            try db.create(table: User.databaseTableName, ifNotExists: true) { t in
                t.column("userId", .blob).primaryKey()
                t.column("publicSigningKey", .blob).notNull()
                t.column("publicName", .text)
            }
            
            try db.create(table: Team.databaseTableName, ifNotExists: true) { t in
                t.column("groupId", .blob).primaryKey()
                t.column("groupKey", .blob).notNull()
                t.column("owner", .blob).notNull()
                t.column("joinMode", .integer).notNull()
                t.column("permissionMode", .integer).notNull()
                t.column("url", .blob).notNull()
                t.column("tag", .text).notNull()
                t.column("name", .text)
                t.column("meetupId", .blob)
                t.column("meetingPoint", .blob)
            }
            
            if try !db.tableExists(Meetup.databaseTableName) {
                try db.create(table: Meetup.databaseTableName, ifNotExists: true) { t in
                    t.column("groupId", .blob).primaryKey()
                    t.column("groupKey", .blob).notNull()
                    t.column("owner", .blob).notNull()
                    t.column("joinMode", .integer).notNull()
                    t.column("permissionMode", .integer).notNull()
                    t.column("tag", .text).notNull()
                    t.column("teamId", .blob)
                        .notNull()
                        .indexed()
                        .references(Team.databaseTableName, column: "groupId", onDelete: .cascade)
                    t.column("meetingPoint", .blob)
                    t.column("locationSharingEnabled", .boolean).notNull()
                }
            }
            
            try db.create(table: Membership.databaseTableName, ifNotExists: true) { t in
                t.column("userId", .blob)
                    .notNull()
                    .references(User.databaseTableName, onDelete: .cascade)
                t.column("groupId", .blob)
                    .notNull()
                t.column("publicSigningKey", .blob).notNull()
                t.column("admin", .boolean).notNull()
                t.column("selfSignedMembershipCertificate", .text)
                t.column("serverSignedMembershipCertificate", .text).notNull()
                t.column("adminSignedMembershipCertificate", .text)
                
                t.primaryKey(["userId", "groupId"])
            }
            
            try db.create(table: EnvelopeCacheRecord.databaseTableName, ifNotExists: true) { t in
                t.column("id", .blob).notNull()
                t.column("senderId", .blob).notNull()
                t.column("state", .integer).notNull()
                t.column("timestamp", .datetime).notNull()
                
                t.primaryKey(["id", "senderId"])
            }
            
            try db.create(table: InboundConversationInvitation.databaseTableName, ifNotExists: true) { t in
                t.column("senderId", .blob)
                    .notNull()
                    .references(User.databaseTableName, onDelete: .cascade)
                t.column("conversationId", .blob).notNull()
                t.column("identityKey", .blob).notNull()
                t.column("ephemeralKey", .blob).notNull()
                t.column("usedOneTimePrekey", .blob)
                t.column("timestamp", .datetime).notNull()
                
                t.primaryKey(["senderId", "conversationId"])
            }
            
            try db.create(table: OutboundConversationInvitation.databaseTableName, ifNotExists: true) { t in
                t.column("receiverId", .blob)
                    .notNull()
                    .references(User.databaseTableName, onDelete: .cascade)
                t.column("conversationId", .blob).notNull()
                t.column("identityKey", .blob).notNull()
                t.column("ephemeralKey", .blob).notNull()
                t.column("usedOneTimePrekey", .blob)
                
                t.primaryKey(["receiverId", "conversationId"])
            }
            
            try db.create(table: ReceivedReset.databaseTableName, ifNotExists: true) { t in
                t.column("senderId", .blob)
                    .notNull()
                    .references(User.databaseTableName, onDelete: .cascade)
                t.column("conversationId", .blob).notNull()
                t.column("timestamp", .datetime).notNull()
                
                t.primaryKey(["senderId", "conversationId"])
            }
            
            try db.create(table: InvalidConversation.databaseTableName, ifNotExists: true) { t in
                t.column("senderId", .blob)
                    .notNull()
                    .references(User.databaseTableName, onDelete: .cascade)
                t.column("conversationId", .blob).notNull()
                t.column("conversationFingerprint", .text).notNull()
                t.column("timestamp", .datetime).notNull()
                t.column("resendResetTimeout", .datetime).notNull()
                
                t.primaryKey(["senderId", "conversationId"])
            }
            
            try db.create(table: ConversationState.databaseTableName, ifNotExists: true) { t in
                t.column("userId", .blob)
                    .notNull()
                    .references(User.databaseTableName, onDelete: .cascade)
                t.column("conversationId", .blob).notNull()
                t.column("rootKey", .blob).notNull()
                t.column("rootChainPublicKey", .blob).notNull()
                t.column("rootChainPrivateKey", .blob).notNull()
                t.column("rootChainRemotePublicKey", .blob)
                t.column("sendingChainKey", .blob)
                t.column("receivingChainKey", .blob)
                t.column("sendMessageNumber", .integer).notNull()
                t.column("receivedMessageNumber", .integer).notNull()
                t.column("previousSendingChainLength", .integer).notNull()
                
                t.primaryKey(["userId", "conversationId"])
            }
            
            try db.create(table: MessageKeyCacheEntry.databaseTableName, ifNotExists: true) { t in
                t.column("conversationId", .blob).notNull()
                t.column("messageNumber", .integer).notNull()
                t.column("publicKey", .blob).notNull()
                t.column("messageKey", .blob).notNull()
                t.column("timestamp", .datetime).notNull()
                
                t.primaryKey(["conversationId", "messageNumber", "publicKey"])
            }
            
            if try !db.tableExists(RawChatMessage.databaseTableName) {
                try db.create(table: RawChatMessage.databaseTableName, ifNotExists: true) { t in
                    t.column("uid", .text).primaryKey()
                    t.column("groupId", .blob)
                        .notNull()
                        .indexed()
                        .references(Team.databaseTableName, column: "groupId", onDelete: .cascade)
                    t.column("type", .text).notNull()
                    t.column("date", .datetime).notNull()
                    t.column("read", .boolean).notNull()
                    
                    t.column("senderId", .text)
                    t.column("isIncoming", .boolean)
                    t.column("status", .text)
                    
                    t.column("text", .text)
                    t.column("imageData", .blob)
                }
            }
            
            if try !db.tableExists(OneTimePrekeyPair.databaseTableName) {
                try db.create(table: OneTimePrekeyPair.databaseTableName, ifNotExists: true) { t in
                    t.autoIncrementedPrimaryKey("id")
                    t.column("publicKey", .blob)
                        .notNull()
                        .unique()
                        .indexed()
                    t.column("privateKey", .blob).notNull()
                }
            }
            
            try db.create(table: Log.databaseTableName, ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("timestamp", .blob).notNull()
                t.column("level", .integer).notNull()
                t.column("process", .text).notNull()
                t.column("message", .text).notNull()
                t.column("file", .text).notNull()
                t.column("function", .text).notNull()
                t.column("line", .integer).notNull()
            }
            
            try db.create(table: LocationSharingState.databaseTableName, ifNotExists: true) { t in
                t.column(LocationSharingState.Columns.userId.name, .blob)
                    .notNull()
                    .indexed()
                    .references(User.databaseTableName, onDelete: .cascade)
                t.column(LocationSharingState.Columns.groupId.name, .blob)
                    .notNull()
                    .indexed()
                    .references(Team.databaseTableName, onDelete: .cascade)
                t.column(LocationSharingState.Columns.enabled.name, .boolean).notNull()
                t.column(LocationSharingState.Columns.lastUpdated.name, .datetime).notNull()
                
                t.primaryKey([LocationSharingState.Columns.userId.name, LocationSharingState.Columns.groupId.name])
            }
        }
    }
}
