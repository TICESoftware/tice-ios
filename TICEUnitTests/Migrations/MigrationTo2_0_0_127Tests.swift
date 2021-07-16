//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//

import Foundation
import Foundation
import XCTest
import GRDB
import PromiseKit

@testable import TICE

class MigrationTo2_0_0_127Tests: XCTestCase {
    
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
            }
        }
    }
    
    func testMigrateTeams() throws {
        let user = User(userId: UserId(), publicSigningKey: Data(), publicName: nil)
        let oldEntry = TeamPre127(groupId: GroupId(), groupKey: Data(), owner: user.userId, joinMode: .open, permissionMode: .everyone, tag: "tag", url: URL(string: "https://example.org")!, name: nil, meetupId: nil)
        
        try database.write { db in
            try user.save(db)
            try oldEntry.save(db)
        }
        
        let completion = expectation(description: "Completion")
        
        firstly { () -> Promise<Void> in
            let migration = MigrationTo2_0_0_127(database: database)
            return migration.migrate()
        }.done {
            try self.database.read { db in
                XCTAssertEqual(try Team.fetchCount(db), 1, "Invalid cache records.")
                
                guard let newEntry = try Team.fetchOne(db) else {
                    XCTFail("Invalid cache records.")
                    return
                }
                
                XCTAssertEqual(oldEntry.groupId, newEntry.groupId, "Invalid records.")
                XCTAssertNil(newEntry.meetingPoint, "Invalid meeting point.")
            }
        }.catch {
            XCTFail(String(describing: $0))
        }.finally {
            completion.fulfill()
        }
        
        wait(for: [completion])
    }
}
