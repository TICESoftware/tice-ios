//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//

import Foundation
import PromiseKit
import Version
import os

enum MigrationManagerError: LocalizedError {
    case migrationError(String)
    case deprecatedVersion

    var errorDescription: String? {
        switch self {
        case .migrationError(let description): return "Error during migration: \(description)"
        case .deprecatedVersion: return "Deprecated app version."
        }
    }
}

protocol MigrationManagerType {
    func migrate() -> Promise<Void>?
    func migrate(to currentVersion: Version) -> Promise<Void>?
}

class MigrationManager: MigrationManagerType {

    var migrations: [Migration.Type] = [MigrationTo1_19_0_120.self, MigrationTo2_0_0_127.self, MigrationTo2_0_0_128.self]

    private let storageManager: VersionStorageManagerType
    private let minPreviousVersion: Version
    private var migrationQueue: [Migration.Type] = []

    init(storageManager: VersionStorageManagerType, minPreviousVersion: Version) {
        self.storageManager = storageManager
        self.minPreviousVersion = minPreviousVersion
    }

    public func migrate() -> Promise<Void>? {
        let currentVersion = Bundle.main.appVersion
        return migrate(to: currentVersion)
    }

    public func migrate(to currentVersion: Version) -> Promise<Void>? {
        guard let storedVersion = storageManager.loadVersion(),
            let migration = migrate(from: storedVersion, to: currentVersion) else {
            storageManager.store(version: currentVersion)
            return nil
        }

        return migration
    }

    private func migrate(from previousVersion: Version, to currentVersion: Version) -> Promise<Void>? {
        logger.info("Checking for migration from \(previousVersion) to \(currentVersion)…")
        
        guard previousVersion < currentVersion else {
            logger.info("Not migrating as old version is as new or newer as \(currentVersion)")
            return nil
        }
        guard minPreviousVersion < previousVersion else {
            logger.info("Not migrating as old version is deprecated")
            return Promise(error: MigrationManagerError.deprecatedVersion)
        }

        migrationQueue = migrations.filter { migration in
            return migration.version > previousVersion && migration.version <= currentVersion
        }

        guard !migrationQueue.isEmpty else {
            logger.info("Not migrating as no migrations registered")
            return nil
        }

        var migrationChain = Promise()
        for migrationType in migrationQueue {
            migrationChain = migrationChain.then { () -> Promise<Void> in
                logger.info("Migration step from \(self.storageManager.loadVersion() ?? "N/A") to \(migrationType.version)…")
                os_log("Migration to %@…", migrationType.version.description)
                let migration = try migrationType.init()
                return migration.migrate()
            }.done {
                self.storageManager.store(version: migrationType.version)
                logger.info("Migration to \(migrationType.version) done")
                os_log("Migration to %@ done.", migrationType.version.description)
            }
        }

        return firstly {
            migrationChain
        }.done { _ in
            self.storageManager.store(version: currentVersion)
            logger.info("All migrations done. Storing current version \(currentVersion)")
            os_log("All migrations done. Storing current version %@", currentVersion.description)
        }
    }
}

public protocol Migration {
    static var version: Version { get }
    init() throws
    func migrate() -> Promise<Void>
}
