//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import GRDB
import PromiseKit
import Version

class MigrationTo2_0_0_127: Migration {
    
    static var version = Version(major: 2, minor: 0, patch: 0, prerelease: "127")
    
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
            try migrateTeamMeetingPoint()
            try createLocationSharingStateTable()
            return Promise()
        }
    }
    
    private func migrateTeamMeetingPoint() throws {
        try database.write { db in
            try db.alter(table: Team.databaseTableName) { t in
                t.add(column: "meetingPoint", .blob)
            }
        }
    }
    
    private func createLocationSharingStateTable() throws {
        try database.write { db in
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
