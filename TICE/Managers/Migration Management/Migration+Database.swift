//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import Valet
import GRDB

enum MigrationError: Error {
    case databaseNotFound
    case databaseKeyNotFound
    case databaseMigrationIncomplete
}

class MigrationHelper {
    
    static func initializeDatabase() throws -> DatabaseWriter {
        let appBundleId = Bundle.main.appBundleId
        let valetId = appBundleId + ".valet"
        let appGroupName = "group." + appBundleId
        
        let valet = Valet.sharedAccessGroupValet(with: Identifier(nonEmpty: valetId)!, accessibility: .afterFirstUnlock)
        
        let storageKey = "databaseKey"
        guard let databaseKey: SecretKey = valet.object(forKey: storageKey) else {
            throw MigrationError.databaseKeyNotFound
        }
        
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            let passphrase = "x'\(databaseKey.hexEncodedString())'"
            try db.usePassphrase(passphrase)
            try db.execute(sql: "PRAGMA cipher_plaintext_header_size = 32")
        }
        
        let fileManager = FileManager.default
        let databaseURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupName)!.appendingPathComponent("db").appendingPathExtension("sqlite")
        
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            logger.debug("No database file existing.")
            throw MigrationError.databaseNotFound
        }
        
        let database: DatabaseWriter
        do {
            database = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
        } catch {
            logger.error("Failed to initialize database queue: \(String(describing: error))")
            throw error
        }
        
        return database
    }
}
