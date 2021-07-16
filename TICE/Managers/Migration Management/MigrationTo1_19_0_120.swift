//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import Valet
import GRDB
import Version
import PromiseKit
import TICEAPIModels

class MigrationTo1_19_0_120: Migration {
    
    static var version = Version(major: 1, minor: 19, patch: 0, prerelease: "120")
    
    let database: DatabaseWriter
    
    required convenience init() throws {
        let database = try MigrationHelper.initializeDatabase()
        self.init(database: database)
    }

    init(database: DatabaseWriter) {
        self.database = database
    }

    func migrate() -> Promise<Void> {
        firstly { () -> Promise<Void> in
            try createMessageKeyCacheEntryTable()
            try migrateConversationStateTable()
            return Promise()
        }
    }

    private func createMessageKeyCacheEntryTable() throws {
        try database.write { db in
            try db.create(table: MessageKeyCacheEntry.databaseTableName, ifNotExists: true) { t in
                t.column("conversationId", .blob).notNull()
                t.column("messageNumber", .integer).notNull()
                t.column("publicKey", .blob).notNull()
                t.column("messageKey", .blob).notNull()
                t.column("timestamp", .datetime).notNull()
                
                t.primaryKey(["conversationId", "messageNumber", "publicKey"])
            }
        }
    }
    
    private func migrateConversationStateTable() throws {
        try database.write { db in
            let tableName = ConversationStatePre120.databaseTableName
            let backupTableName = tableName + "_BACKUP_120"
            
            if try db.tableExists(backupTableName) {
                // This migration has been run before. Restoring the backup before proceeding.
                try db.drop(table: tableName)
                try db.rename(table: backupTableName, to: tableName)
            }
            
            let records = try ConversationStatePre120.fetchAll(db)

            try db.rename(table: tableName, to: backupTableName)

            try db.create(table: tableName, ifNotExists: true) { t in
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
            
            let migratedRecords = records.map(ConversationStatePost120.init(conversationStatePre120:))

            for record in migratedRecords {
                try record.save(db)
            }
        }
    }
}

struct ConversationStatePre120: Codable, PersistableRecord, FetchableRecord {
    static var databaseTableName: String = "conversationState"
    
    let userId: UserId
    let conversationId: ConversationId

    let rootKey: SecretKey
    let rootChainPublicKey: PublicKey
    let rootChainPrivateKey: PrivateKey
    let rootChainRemotePublicKey: PublicKey?
    let sendingChainKey: SecretKey?
    let receivingChainKey: SecretKey?

    let sendMessageNumber: Int
    let receivedMessageNumber: Int
    let previousSendingChainLength: Int
    let messageKeyCache: Data?
}

struct ConversationStatePost120: Codable, PersistableRecord, FetchableRecord {
    static var databaseTableName: String = "conversationState"
    
    let userId: UserId
    let conversationId: ConversationId

    let rootKey: SecretKey
    let rootChainPublicKey: PublicKey
    let rootChainPrivateKey: PrivateKey
    let rootChainRemotePublicKey: PublicKey?
    let sendingChainKey: SecretKey?
    let receivingChainKey: SecretKey?

    let sendMessageNumber: Int
    let receivedMessageNumber: Int
    let previousSendingChainLength: Int
    
    init(conversationStatePre120: ConversationStatePre120) {
        userId = conversationStatePre120.userId
        conversationId = conversationStatePre120.conversationId
        rootKey = conversationStatePre120.rootKey
        rootChainPublicKey = conversationStatePre120.rootChainPublicKey
        rootChainPrivateKey = conversationStatePre120.rootChainPrivateKey
        rootChainRemotePublicKey = conversationStatePre120.rootChainRemotePublicKey
        sendingChainKey = conversationStatePre120.sendingChainKey
        receivingChainKey = conversationStatePre120.receivingChainKey
        sendMessageNumber = conversationStatePre120.sendMessageNumber
        receivedMessageNumber = conversationStatePre120.receivedMessageNumber
        previousSendingChainLength = conversationStatePre120.previousSendingChainLength
    }
}
