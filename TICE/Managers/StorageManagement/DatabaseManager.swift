//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import GRDB
import Valet
import Swinject

enum DatabaseManagerError: LocalizedError {
    case initializationFailed(Error?)
    case noDatabaseKey
    case databaseKeyGenerationFailed

    var errorDescription: String? {
        switch self {
        case .initializationFailed: return L10n.Error.DatabaseManager.initializationFailed
        case .noDatabaseKey: return L10n.Error.DatabaseManager.noDatabaseKey
        case .databaseKeyGenerationFailed: return L10n.Error.DatabaseManager.databaseKeyGenerationFailed
        }
    }
}

protocol DatabaseManagerType {
    func setupDatabase() throws
}

class DatabaseManager: DatabaseManagerType {

    let valet: Valet
    let container: Container
    let cryptoManager: CryptoManagerType
    let tableCreator: TableCreatorType
    let databaseURL: URL
    let databaseKeyLength: Int

    private var database: DatabaseWriter?

    init(valet: Valet, container: Container, cryptoManager: CryptoManagerType, tableCreator: TableCreatorType, databaseURL: URL, databaseKeyLength: Int) {
        self.valet = valet
        self.container = container
        self.cryptoManager = cryptoManager
        self.tableCreator = tableCreator
        self.databaseURL = databaseURL
        self.databaseKeyLength = databaseKeyLength
    }

    func setupDatabase() throws {
        let db: DatabaseWriter
        if CommandLine.arguments.contains("UITESTING") {
            db = DatabaseQueue()
        } else {
            db = try setupSharedDatabase()
        }

        container.register(DatabaseWriter.self, factory: { _ in db }).inObjectScope(.container)
        self.database = db

        try tableCreator.createTablesIfNecessary(database: db)
    }

    private func setupSharedDatabase() throws -> DatabaseWriter {
        let databaseKeyStorageKey = "databaseKey"

        let databaseKey: SecretKey
        if let savedKey = valet.object(forKey: databaseKeyStorageKey) {
            databaseKey = savedKey
        } else {
            logger.info("No database key in storage. Generating new key.")
            guard let generatedKey = cryptoManager.generateDatabaseKey(length: databaseKeyLength) else {
                throw DatabaseManagerError.databaseKeyGenerationFailed
            }
            valet.set(object: generatedKey, forKey: databaseKeyStorageKey)
            databaseKey = generatedKey
        }

        return try DatabaseManager.openSharedDatabase(at: databaseURL, databaseKey: databaseKey)
    }

    private class func openSharedDatabase(at databaseURL: URL, databaseKey: SecretKey) throws -> DatabaseWriter {
        var configuration = Configuration()
        configuration.busyMode = .timeout(2.0)
        configuration.defaultTransactionKind = .immediate
        configuration.prepareDatabase { db in
            let passphrase = "x'\(databaseKey.hexEncodedString())'"
            try db.usePassphrase(passphrase)

            // We need the first 32 bytes of the database file to remain in plaintext because iOS needs to identify the file as a database.
            try db.execute(sql: "PRAGMA cipher_plaintext_header_size = 32")
        }

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinatorError: NSError?
        var dbPool: DatabasePool?
        var dbError: Error?

        coordinator.coordinate(writingItemAt: databaseURL, options: .forMerging, error: &coordinatorError, byAccessor: { url in
            do {
                dbPool = try DatabasePool(path: url.path, configuration: configuration)
            } catch {
                dbError = error
            }
        })

        if let error = coordinatorError {
            logger.error("Could access database file: \(String(describing: error))")
            throw DatabaseManagerError.initializationFailed(error)
        }

        if let error = dbError {
            logger.error("Could not open database: \(String(describing: error))")
            throw DatabaseManagerError.initializationFailed(error)
        }

        guard let db = dbPool else {
            logger.error("Database not available although we haven't encountered any errors.")
            throw DatabaseManagerError.initializationFailed(nil)
        }

        return db
    }
}
