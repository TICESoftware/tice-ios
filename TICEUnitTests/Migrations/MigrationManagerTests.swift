//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import PromiseKit
import Version
import XCTest
import GRDB
import Valet
import Cuckoo

@testable import TICE

protocol ClosureMigration: Migration {
    static var closure: (() -> Void)? { get set }
}

extension ClosureMigration {
    func migrate() -> Promise<Void> {
        Self.closure?()
        return .init()
    }
}

class MigrationManagerTests: XCTestCase {
    var versionStorageManager: MockVersionStorageManagerType!
    var userDefaultsSuiteName: String!
    var valet: Valet!
    var userDefaults: UserDefaults!
    var database: DatabaseWriter!

    var signedInUserManager: MockSignedInUserManagerType!
    var backend: MockTICEAPI!
    var cryptoManager: MockCryptoManagerType!
    var decoder: JSONDecoder!

    var migrationManager: MigrationManager!

    override func setUp() {
        super.setUp()

        versionStorageManager = MockVersionStorageManagerType()
        userDefaultsSuiteName = "migrationManagerTestAppSuite"
        valet = Valet.valet(with: Identifier(nonEmpty: "migrationManagerTestValet")!, accessibility: .always)
        userDefaults = UserDefaults(suiteName: userDefaultsSuiteName)!
        database = DatabaseQueue()

        signedInUserManager = MockSignedInUserManagerType()
        backend = MockTICEAPI()
        cryptoManager = MockCryptoManagerType()
        decoder = JSONDecoder.decoderWithFractionalSeconds

        migrationManager = MigrationManager(storageManager: versionStorageManager, minPreviousVersion: Version(major: 1, minor: 1, patch: 1, prerelease: "100"))
    }

    override func tearDown() {
        valet.removeAllObjects()
        userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)

        super.tearDown()
    }

    func testFreshInstall() {
        stub(versionStorageManager) { stub in
            when(stub.loadVersion()).thenReturn(nil)
            when(stub.store(version: Version("1.2.0"))).thenDoNothing()
        }

        let exp = self.expectation(description: "Migration should not be called")
        exp.isInverted = true
        
        struct MockMigration: ClosureMigration {
            static var closure: (() -> Void)?
            static let version: Version = "1.1.0"
            init() throws {}
        }
        
        MockMigration.closure = {
            exp.fulfill()
        }
        migrationManager.migrations.append(MockMigration.self)

        XCTAssertNil(migrationManager.migrate(to: "1.2.0"))

        wait(for: [exp])
    }

    func testMigration() {
        stub(versionStorageManager) { stub in
            when(stub.loadVersion()).thenReturn("1.1.1")
            when(stub.store(version: Version("1.2.0"))).thenDoNothing()
        }

        let exp = self.expectation(description: "Migration handler called")
        struct MockMigration: ClosureMigration {
            static var closure: (() -> Void)?
            static let version: Version = "1.2.0"
            init() throws {}
        }
        
        MockMigration.closure = {
            exp.fulfill()
        }
        migrationManager.migrations.append(MockMigration.self)

        _ = migrationManager.migrate(to: "1.2.0")

        wait(for: [exp])
    }

    func testOldMigration() {
        stub(versionStorageManager) { stub in
            when(stub.loadVersion()).thenReturn("1.2.0")
            when(stub.store(version: any())).thenDoNothing()
        }

        let exp = self.expectation(description: "Migration to 2 should not be called")
        exp.isInverted = true

        struct MockMigration_1: ClosureMigration {
            static var closure: (() -> Void)?
            static let version: Version = "1.1.0"
            init() throws {}
        }
        struct MockMigration_2: ClosureMigration {
            static var closure: (() -> Void)?
            static let version: Version = "1.2.0"
            init() throws {}
        }
        
        MockMigration_1.closure = {
            exp.fulfill()
        }
        MockMigration_2.closure = {
            exp.fulfill()
        }
        migrationManager.migrations.append(MockMigration_1.self)
        migrationManager.migrations.append(MockMigration_2.self)

        _ = migrationManager.migrate(to: "1.3.0")

        wait(for: [exp])
    }

    func testOldAndNewMigration() {
        stub(versionStorageManager) { stub in
            when(stub.loadVersion()).thenReturn("1.2.0")
            when(stub.store(version: any())).thenDoNothing()
        }

        let exp2 = self.expectation(description: "Migration to 2 should not be called")
        exp2.isInverted = true
        let exp3 = self.expectation(description: "Migration to 3 should be called")

        struct MockMigration_2: ClosureMigration {
            static var closure: (() -> Void)?
            static let version: Version = "1.2.0"
            init() throws {}
        }
        struct MockMigration_3: ClosureMigration {
            static var closure: (() -> Void)?
            static let version: Version = "1.3.0"
            init() throws {}
        }
        
        MockMigration_2.closure = {
            exp2.fulfill()
        }
        MockMigration_3.closure = {
            exp3.fulfill()
        }
        migrationManager.migrations.append(MockMigration_2.self)
        migrationManager.migrations.append(MockMigration_3.self)

        _ = migrationManager.migrate(to: "1.3.0")

        wait(for: [exp2, exp3])
    }
    
    func testDeprecatedVersion() {
        stub(versionStorageManager) { stub in
            when(stub.loadVersion()).thenReturn("1.0.0")
        }
        
        guard let migration = migrationManager.migrate(to: "1.2.0") else {
            XCTFail("No migration promise")
            return
        }
        
        let exp = expectation(description: "MigrationError")
        
        migration.catch { error in
            guard case MigrationManagerError.deprecatedVersion = error else {
                XCTFail("Unexpected error")
                return
            }
            exp.fulfill()
        }
        
        wait(for: [exp])
    }
    
    func testMigrationOrder() throws {
        let versions = migrationManager.migrations.map { $0.version }
        XCTAssertEqual(versions, versions.sorted())
    }
    
    func testIncludesAllMigrations() throws {
        let registeredMigrationVersions = migrationManager.migrations.map { $0.version }
        let allMigrationVersions = __allMigrations.map { $0.version }
        XCTAssertEqual(Set(registeredMigrationVersions), Set(allMigrationVersions))
    }
}
