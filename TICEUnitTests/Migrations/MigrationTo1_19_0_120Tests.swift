//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import Foundation
import XCTest
import GRDB
import PromiseKit
import TICEAPIModels

@testable import TICE

class MigrationTo1_19_0_120Tests: XCTestCase {

    var database: DatabaseWriter!

    override func setUpWithError() throws {
        super.setUp()

        database = DatabaseQueue()
        try createOldTables()
    }
    
    private func createOldTables() throws {
        try database.write { db in
            try db.create(table: User.databaseTableName, ifNotExists: true) { t in
                t.column("userId", .blob).primaryKey()
                t.column("publicSigningKey", .blob).notNull()
                t.column("publicName", .text)
            }
            
            try db.create(table: "conversationState", ifNotExists: true) { t in
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
                t.column("messageKeyCache", .blob).notNull()

                t.primaryKey(["userId", "conversationId"])
            }
        }
    }

    func testMigrateConversationState() throws {
        let user = User(userId: UserId(), publicSigningKey: Data(), publicName: nil)
        let oldEntry = ConversationStatePre120(userId: user.userId,
                                               conversationId: ConversationId(), rootKey: SecretKey(),
                                               rootChainPublicKey: PublicKey(),
                                               rootChainPrivateKey: PrivateKey(),
                                               rootChainRemotePublicKey: PublicKey(),
                                               sendingChainKey: SecretKey(),
                                               receivingChainKey: SecretKey(),
                                               sendMessageNumber: 1, receivedMessageNumber: 2,
                                               previousSendingChainLength: 3,
                                               messageKeyCache: Data())
        try database.write { db in
            try user.save(db)
            try oldEntry.save(db)
        }

        let completion = expectation(description: "Completion")

        firstly { () -> Promise<Void> in
            let migration = MigrationTo1_19_0_120(database: database)
            return migration.migrate()
        }.done {
            try self.database.read { db in
                XCTAssertEqual(try ConversationStatePost120.fetchCount(db), 1, "Invalid cache records.")

                guard let newEntry = try ConversationStatePost120.fetchOne(db) else {
                    XCTFail("Invalid cache records.")
                    return
                }

                XCTAssertEqual(oldEntry.userId, newEntry.userId, "Invalid records.")
                XCTAssertEqual(oldEntry.conversationId, newEntry.conversationId, "Invalid records.")
                XCTAssertEqual(oldEntry.rootKey, newEntry.rootKey, "Invalid records.")
                XCTAssertEqual(oldEntry.rootChainPublicKey, newEntry.rootChainPublicKey, "Invalid records.")
                XCTAssertEqual(oldEntry.rootChainPrivateKey, newEntry.rootChainPrivateKey, "Invalid records.")
                XCTAssertEqual(oldEntry.rootChainRemotePublicKey, newEntry.rootChainRemotePublicKey, "Invalid records.")
                XCTAssertEqual(oldEntry.sendingChainKey, newEntry.sendingChainKey, "Invalid records.")
                XCTAssertEqual(oldEntry.receivingChainKey, newEntry.receivingChainKey, "Invalid records.")
                XCTAssertEqual(oldEntry.sendMessageNumber, newEntry.sendMessageNumber, "Invalid records.")
                XCTAssertEqual(oldEntry.receivedMessageNumber, newEntry.receivedMessageNumber, "Invalid records.")
                XCTAssertEqual(oldEntry.previousSendingChainLength, newEntry.previousSendingChainLength, "Invalid records.")
            }
        }.catch {
            XCTFail(String(describing: $0))
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }
    
    func testMigrateConversationStateFromBroken122Build() throws {
        let user = User(userId: UserId(), publicSigningKey: Data(), publicName: nil)
        let oldEntry = ConversationStatePre120(userId: user.userId,
                                               conversationId: ConversationId(), rootKey: SecretKey(),
                                               rootChainPublicKey: PublicKey(),
                                               rootChainPrivateKey: PrivateKey(),
                                               rootChainRemotePublicKey: PublicKey(),
                                               sendingChainKey: SecretKey(),
                                               receivingChainKey: SecretKey(),
                                               sendMessageNumber: 1, receivedMessageNumber: 2,
                                               previousSendingChainLength: 3,
                                               messageKeyCache: Data())
        try database.write { db in
            try user.save(db)
            try oldEntry.save(db)
        }

        let completion = expectation(description: "Completion")

        firstly { () -> Promise<Void> in
            let migration = MigrationTo1_19_0_120(database: database)
            return migration.migrate()
        }.done {
            try self.database.write { db in
                try db.drop(table: "conversationState_BACKUP_120")
            }
        }.then { () -> Promise<Void> in
            let migration = MigrationTo1_19_0_120(database: self.database)
            return migration.migrate()
        }.done {
            try self.database.read { db in
                XCTAssertEqual(try ConversationStatePost120.fetchCount(db), 1, "Invalid cache records.")

                guard let newEntry = try ConversationStatePost120.fetchOne(db) else {
                    XCTFail("Invalid cache records.")
                    return
                }

                XCTAssertEqual(oldEntry.userId, newEntry.userId, "Invalid records.")
                XCTAssertEqual(oldEntry.conversationId, newEntry.conversationId, "Invalid records.")
                XCTAssertEqual(oldEntry.rootKey, newEntry.rootKey, "Invalid records.")
                XCTAssertEqual(oldEntry.rootChainPublicKey, newEntry.rootChainPublicKey, "Invalid records.")
                XCTAssertEqual(oldEntry.rootChainPrivateKey, newEntry.rootChainPrivateKey, "Invalid records.")
                XCTAssertEqual(oldEntry.rootChainRemotePublicKey, newEntry.rootChainRemotePublicKey, "Invalid records.")
                XCTAssertEqual(oldEntry.sendingChainKey, newEntry.sendingChainKey, "Invalid records.")
                XCTAssertEqual(oldEntry.receivingChainKey, newEntry.receivingChainKey, "Invalid records.")
                XCTAssertEqual(oldEntry.sendMessageNumber, newEntry.sendMessageNumber, "Invalid records.")
                XCTAssertEqual(oldEntry.receivedMessageNumber, newEntry.receivedMessageNumber, "Invalid records.")
                XCTAssertEqual(oldEntry.previousSendingChainLength, newEntry.previousSendingChainLength, "Invalid records.")
            }
        }.catch {
            XCTFail(String(describing: $0))
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }
}
