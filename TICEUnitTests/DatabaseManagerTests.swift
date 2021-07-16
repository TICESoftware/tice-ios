//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import XCTest
import Swinject
import Valet
import GRDB
import TICEAPIModels
import Cuckoo

@testable import TICE

class DatabaseManagerTests: XCTestCase {

    var valet: Valet!
    var container: Container!
    var cryptoManager: MockCryptoManagerType!
    var databaseURL: URL!
    let databaseKeyLength = 48
    let tableCreator = TableCreator()

    var databaseManager: DatabaseManager!

    override func setUpWithError() throws {
        super.setUp()

        valet = Valet.valet(with: Identifier(nonEmpty: "databaseManagerTests")!, accessibility: .always)
        container = Container()
        cryptoManager = MockCryptoManagerType()

        let fileManager = FileManager.default
        databaseURL = fileManager.temporaryDirectory.appendingPathComponent("testDB.sqlite")

        if fileManager.fileExists(atPath: databaseURL.path) {
            try fileManager.removeItem(at: databaseURL)
        }

        databaseManager = DatabaseManager(valet: valet, container: container, cryptoManager: cryptoManager, tableCreator: tableCreator, databaseURL: databaseURL, databaseKeyLength: databaseKeyLength)
    }

    override func tearDownWithError() throws {
        container.removeAll()
        try FileManager.default.removeItem(at: databaseURL)

        valet.removeAllObjects()

        super.tearDown()
    }

    func testSetupDatabaseCreate() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path), "Database should not exist")

        let databaseKey = Data(count: databaseKeyLength)
        stub(cryptoManager) { stub in
            when(stub.generateDatabaseKey(length: databaseKeyLength)).thenReturn(databaseKey)
        }

        try databaseManager.setupDatabase()

        guard let database = container.resolve(DatabaseWriter.self) else {
            XCTFail("Database setup failed")
            return
        }

        verify(cryptoManager).generateDatabaseKey(length: databaseKeyLength)
        XCTAssertEqual(valet.object(forKey: "databaseKey"), databaseKey, "Invalid database key stored")

        try database.read { db in
            XCTAssertTrue(try db.tableExists(User.databaseTableName), "Table not existing")
        }

        var configuration = Configuration()
        configuration.busyMode = .timeout(2.0)
        configuration.defaultTransactionKind = .immediate
        configuration.prepareDatabase { db in
            let passphrase = "x'\(databaseKey.hexEncodedString())'"
            try db.usePassphrase(passphrase)

            // We need the first 32 bytes of the database file to remain in plaintext because iOS needs to identify the file as a database.
            try db.execute(sql: "PRAGMA cipher_plaintext_header_size = 32")
        }

        let dbPool = try DatabasePool(path: databaseURL.path, configuration: configuration)

        try dbPool.read { db in
            XCTAssertTrue(try db.tableExists(User.databaseTableName), "Table not existing")
        }
    }

    func testSetupDatabaseExisting() throws {
        let databaseKey = Data(count: databaseKeyLength)
        valet.set(object: databaseKey, forKey: "databaseKey")

        var configuration = Configuration()
        configuration.busyMode = .timeout(2.0)
        configuration.defaultTransactionKind = .immediate
        configuration.prepareDatabase { db in
            let passphrase = "x'\(databaseKey.hexEncodedString())'"
            try db.usePassphrase(passphrase)

            // We need the first 32 bytes of the database file to remain in plaintext because iOS needs to identify the file as a database.
            try db.execute(sql: "PRAGMA cipher_plaintext_header_size = 32")
        }

       _ = try DatabasePool(path: databaseURL.path, configuration: configuration)

        XCTAssertTrue(FileManager.default.fileExists(atPath: databaseURL.path), "Database should exist")

        try databaseManager.setupDatabase()

        guard let database = container.resolve(DatabaseWriter.self) else {
            XCTFail("Database setup failed")
            return
        }

        try database.read { db in
            XCTAssertTrue(try db.tableExists(User.databaseTableName), "Table not existing")
        }
    }

    func testCreateTables() throws {
        let databaseKey = Data(count: databaseKeyLength)
        stub(cryptoManager) { stub in
            when(stub.generateDatabaseKey(length: databaseKeyLength)).thenReturn(databaseKey)
        }
        
        try databaseManager.setupDatabase()

        guard let database = container.resolve(DatabaseWriter.self) else {
            XCTFail("Database setup failed")
            return
        }

        try database.read { db in
            XCTAssertTrue(try db.tableExists(User.databaseTableName), "Table not existing")
            XCTAssertTrue(try db.tableExists(Team.databaseTableName), "Table not existing")
            XCTAssertTrue(try db.tableExists(Meetup.databaseTableName), "Table not existing")
            XCTAssertTrue(try db.tableExists(Membership.databaseTableName), "Table not existing")
            XCTAssertTrue(try db.tableExists(EnvelopeCacheRecord.databaseTableName), "Table not existing")
            XCTAssertTrue(try db.tableExists(InboundConversationInvitation.databaseTableName), "Table not existing")
            XCTAssertTrue(try db.tableExists(OutboundConversationInvitation.databaseTableName), "Table not existing")
            XCTAssertTrue(try db.tableExists(InvalidConversation.databaseTableName), "Table not existing")
            XCTAssertTrue(try db.tableExists(ConversationState.databaseTableName), "Table not existing")
            XCTAssertTrue(try db.tableExists(RawChatMessage.databaseTableName), "Table not existing")
        }
    }

    func testCascadeMeetupDeletion() throws {
        let databaseKey = Data(count: databaseKeyLength)
        stub(cryptoManager) { stub in
            when(stub.generateDatabaseKey(length: databaseKeyLength)).thenReturn(databaseKey)
        }

        try databaseManager.setupDatabase()

        guard let database = container.resolve(DatabaseWriter.self) else {
            XCTFail("Database setup failed")
            return
        }

        let meetupId = GroupId()
        let team = Team(groupId: GroupId(), groupKey: Data(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "teamTag", url: URL(string: "https://develop.tice.app/group/1")!, name: nil, meetupId: meetupId)
        let meetup = Meetup(groupId: meetupId, groupKey: Data(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "meetupTag", teamId: team.groupId, meetingPoint: nil, locationSharingEnabled: true)

        try database.write { db in
            try team.save(db)
            try meetup.save(db)

            XCTAssertEqual(try Meetup.fetchCount(db), 1, "Invalid meetups")

            try team.delete(db)

            XCTAssertEqual(try Meetup.fetchCount(db), 0, "Invalid meetups")
        }
    }

    func testCascadeChatMessageDeletion() throws {
        let databaseKey = Data(count: databaseKeyLength)
        stub(cryptoManager) { stub in
            when(stub.generateDatabaseKey(length: databaseKeyLength)).thenReturn(databaseKey)
        }

        try databaseManager.setupDatabase()

        guard let database = container.resolve(DatabaseWriter.self) else {
            XCTFail("Database setup failed")
            return
        }

        let team = Team(groupId: GroupId(), groupKey: Data(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "teamTag", url: URL(string: "https://develop.tice.app/group/1")!, name: nil, meetupId: nil)

        let messageModel = MessageModel(uid: UUID().uuidString, senderId: UserId().uuidString, type: "type", isIncoming: false, date: Date(), status: .success, read: true)
        let textMessage = TextMessage(messageModel: messageModel, text: "text")
        let rawChatMessage = RawChatMessage(message: textMessage, groupId: team.groupId)

        try database.write { db in
            try team.save(db)
            try rawChatMessage.save(db)

            XCTAssertEqual(try RawChatMessage.fetchCount(db), 1, "Invalid chat messages")

            try team.delete(db)

            XCTAssertEqual(try RawChatMessage.fetchCount(db), 0, "Invalid chat messages")
        }
    }

    func testCascadeConversationInformationDeletion() throws {
        let databaseKey = Data(count: databaseKeyLength)
        stub(cryptoManager) { stub in
            when(stub.generateDatabaseKey(length: databaseKeyLength)).thenReturn(databaseKey)
        }

        try databaseManager.setupDatabase()

        guard let database = container.resolve(DatabaseWriter.self) else {
            XCTFail("Database setup failed")
            return
        }

        let user = User(userId: UserId(), publicSigningKey: Data(), publicName: nil)

        let conversationInvitation = ConversationInvitation(identityKey: Data(), ephemeralKey: Data(), usedOneTimePrekey: nil)
        let inboundConversationInvitation = InboundConversationInvitation(senderId: user.userId, conversationId: ConversationId(), timestamp: Date(), conversationInvitation: conversationInvitation)
        let outboundConversationInvitation = OutboundConversationInvitation(receiverId: user.userId, conversationId: ConversationId(), conversationInvitation: conversationInvitation)
        let invalidConversation = InvalidConversation(senderId: user.userId, conversationId: ConversationId(), conversationFingerprint: "", timestamp: Date(), resendResetTimeout: Date())
        let conversationState = ConversationState(userId: user.userId, conversationId: ConversationId(), rootKey: Data(), rootChainPublicKey: Data(), rootChainPrivateKey: Data(), rootChainRemotePublicKey: nil, sendingChainKey: nil, receivingChainKey: nil, sendMessageNumber: 0, receivedMessageNumber: 0, previousSendingChainLength: 0)

        try database.write { db in
            try user.save(db)
            try inboundConversationInvitation.save(db)
            try outboundConversationInvitation.save(db)
            try invalidConversation.save(db)
            try conversationState.save(db)

            XCTAssertEqual(try InboundConversationInvitation.fetchCount(db), 1, "Invalid conversation information")
            XCTAssertEqual(try OutboundConversationInvitation.fetchCount(db), 1, "Invalid conversation information")
            XCTAssertEqual(try InvalidConversation.fetchCount(db), 1, "Invalid conversation information")
            XCTAssertEqual(try ConversationState.fetchCount(db), 1, "Invalid conversation information")

            try user.delete(db)

            XCTAssertEqual(try InboundConversationInvitation.fetchCount(db), 0, "Invalid conversation information")
            XCTAssertEqual(try OutboundConversationInvitation.fetchCount(db), 0, "Invalid conversation information")
            XCTAssertEqual(try InvalidConversation.fetchCount(db), 0, "Invalid conversation information")
            XCTAssertEqual(try ConversationState.fetchCount(db), 0, "Invalid conversation information")
        }
    }
}
