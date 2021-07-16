//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import GRDB

class UserStorageManager: UserStorageManagerType {
    let database: DatabaseWriter

    init(database: DatabaseWriter) {
        self.database = database
    }

    func store(_ user: User) throws {
        try database.write { db in
            try user.save(db)
        }
    }

    func loadUser(userId: UserId) throws -> User? {
        try database.read { db in
            try User.fetchOne(db, key: userId)
        }
    }

    func loadUsers() throws -> [User] {
        try database.read { db in
            try User.fetchAll(db)
        }
    }

    func deleteAllData() {
        do {
            try database.write { try $0.drop(table: User.databaseTableName) }
        } catch {
            logger.error("Error during deletion of all user data: \(String(describing: error))")
        }
    }
}
