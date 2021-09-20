//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import XCTest
import GRDB
import TICEAPIModels

@testable import TICE

class ChatStorageManagerTests: XCTestCase {
    var database: DatabaseWriter!
    
    var chatStorageManager: ChatStorageManager!
    
    override func setUpWithError() throws {
        database = DatabaseQueue()
        try TableCreator().createTablesIfNecessary(database: database)
        chatStorageManager = ChatStorageManager(database: database)
    }
    
    func testUnreadMessageCount() throws {
        let teamId = GroupId()
        let team = Team(groupId: teamId, groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "/")!)
        try database.write { try team.save($0) }
        
        let messageModel = MessageModel(uid: UUID().uuidString, senderId: UserId().uuidString, type: ChatComponent.text.rawValue, isIncoming: true, date: Date(), status: .success, read: false)
        let textMessage = TextMessage(messageModel: messageModel, text: "Text1")
        chatStorageManager.save(messages: [textMessage], for: teamId)
        
        XCTAssertEqual(try chatStorageManager.unreadMessageCount(), 1)
    }
    
    func testUnreadMessageCountForMultipleGroups() throws {
        
        let teamId1 = GroupId()
        let team1 = Team(groupId: teamId1, groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "/")!)
        try database.write { try team1.save($0) }
        
        let teamId2 = GroupId()
        let team2 = Team(groupId: teamId2, groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "/")!)
        try database.write { try team2.save($0) }
        
        let messageModel1 = MessageModel(uid: UUID().uuidString, senderId: UserId().uuidString, type: ChatComponent.text.rawValue, isIncoming: true, date: Date(), status: .success, read: false)
        let textMessage1 = TextMessage(messageModel: messageModel1, text: "Text1")
        chatStorageManager.save(messages: [textMessage1], for: teamId1)
        
        let messageModel2 = MessageModel(uid: UUID().uuidString, senderId: UserId().uuidString, type: ChatComponent.text.rawValue, isIncoming: true, date: Date(), status: .success, read: false)
        let textMessage2 = TextMessage(messageModel: messageModel2, text: "Text2")
        
        let messageModel3 = MessageModel(uid: UUID().uuidString, senderId: UserId().uuidString, type: ChatComponent.text.rawValue, isIncoming: true, date: Date(), status: .success, read: false)
        let textMessage3 = TextMessage(messageModel: messageModel3, text: "Text2")
        chatStorageManager.save(messages: [textMessage2, textMessage3], for: teamId2)
        
        XCTAssertEqual(try chatStorageManager.unreadMessageCount(for: teamId1), 1)
        XCTAssertEqual(try chatStorageManager.unreadMessageCount(for: teamId2), 2)
    }
}
