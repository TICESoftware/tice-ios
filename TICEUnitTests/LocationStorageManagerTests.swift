//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import XCTest
import GRDB
import TICEAPIModels

@testable import TICE

class LocationStorageManagerTests: XCTestCase {
    
    var userDefaults: UserDefaults!
    var encoder: JSONEncoder!
    var decoder: JSONDecoder!
    var database: DatabaseWriter!
    var tableCreator: TableCreatorType!
    
    var locationStorageManager: LocationStorageManager!
    
    var userDefaultsSuiteLabel: String { "UnitTest-\(name)" }
    
    override func setUpWithError() throws {
        userDefaults = UserDefaults(suiteName: userDefaultsSuiteLabel)
        reset(userDefaults: userDefaults)
        
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        database = DatabaseQueue()
        tableCreator = TableCreator()
        
        locationStorageManager = LocationStorageManager(userDefaults: userDefaults, encoder: encoder, decoder: decoder, database: database)
        
        try database.write { db in
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
                t.column("meetingPoint", .blob)
            }
            
            try db.create(table: Membership.databaseTableName, ifNotExists: true) { t in
                t.column("userId", .blob)
                    .notNull()
                t.column("groupId", .blob)
                    .notNull()
                t.column("publicSigningKey", .blob).notNull()
                t.column("admin", .boolean).notNull()
                t.column("selfSignedMembershipCertificate", .text)
                t.column("serverSignedMembershipCertificate", .text).notNull()
                t.column("adminSignedMembershipCertificate", .text)

                t.primaryKey(["userId", "groupId"])
            }
            
            try db.create(table: LocationSharingState.databaseTableName, ifNotExists: true) { t in
                t.column(LocationSharingState.Columns.userId.name, .blob)
                    .notNull()
                    .indexed()
                t.column(LocationSharingState.Columns.groupId.name, .blob)
                    .notNull()
                    .indexed()
                t.column(LocationSharingState.Columns.enabled.name, .boolean).notNull()
                t.column(LocationSharingState.Columns.lastUpdated.name, .datetime).notNull()
                
                t.primaryKey([LocationSharingState.Columns.userId.name, LocationSharingState.Columns.groupId.name])
            }
        }
    }
    
    func reset(userDefaults: UserDefaults) {
        let keys = userDefaults.dictionaryRepresentation().keys
        keys.forEach(userDefaults.removeValue(for:))
    }
    
    func testStoreLastLocation() throws {
        let location = Location(latitude: 52.0, longitude: 13.0)
        
        try locationStorageManager.store(lastLocation: location)
        
        let storedLocation = try userDefaults.data(forKey: LocationStorageManager.StorageKey.lastLocation.rawValue).map { try decoder.decode(Location.self, from: $0) }
        
        XCTAssertEqual(storedLocation, location)
        
        try locationStorageManager.store(lastLocation: nil)
        
        XCTAssertNil(userDefaults.data(forKey: LocationStorageManager.StorageKey.lastLocation.rawValue))
    }
    
    func testLoadLastLocation() throws {
        let location = Location(latitude: 52.0, longitude: 13.0)
        
        XCTAssertNil(try locationStorageManager.loadLastLocation())
        
        userDefaults.set(try encoder.encode(location), forKey: LocationStorageManager.StorageKey.lastLocation.rawValue)
        
        XCTAssertEqual(try locationStorageManager.loadLastLocation(), location)
    }
    
    func testLocationRequirement() throws {
        let userId = UserId()
        let team1 = Team(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "/")!)
        
        XCTAssertFalse(try locationStorageManager.locationRequired(userId: userId))
        
        try database.write { try team1.save($0) }
        
        XCTAssertFalse(try locationStorageManager.locationRequired(userId: userId))
        
        try locationStorageManager.storeLocationSharingState(userId: userId, groupId: team1.groupId, enabled: false, lastUpdated: Date())
        
        XCTAssertFalse(try locationStorageManager.locationRequired(userId: userId))
        
        try locationStorageManager.storeLocationSharingState(userId: userId, groupId: team1.groupId, enabled: true, lastUpdated: Date())
        
        XCTAssertTrue(try locationStorageManager.locationRequired(userId: userId))
    }
    
    func testLocationRequirementObservation() throws {
        let userId = UserId()
        let team1 = Team(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "/")!)
        
        var locationRequired = false
        let observationCallbackLock = DispatchSemaphore(value: 0)
        let observerToken = locationStorageManager.observeLocationRequirement(userId: userId, queue: .global()) {
            locationRequired = $0
            observationCallbackLock.signal()
        }
        
        observationCallbackLock.wait()
        
        try locationStorageManager.storeLocationSharingState(userId: userId, groupId: team1.groupId, enabled: false, lastUpdated: Date())
        
        observationCallbackLock.wait()
        XCTAssertFalse(locationRequired)
        
        try locationStorageManager.storeLocationSharingState(userId: userId, groupId: team1.groupId, enabled: true, lastUpdated: Date())
        
        observationCallbackLock.wait()
        XCTAssertTrue(locationRequired)
        
        observerToken.cancel()
    }
    
    func testDeleteAllData() throws {
        let location = Location(latitude: 52.0, longitude: 13.0)
        userDefaults.set(try encoder.encode(location), forKey: LocationStorageManager.StorageKey.lastLocation.rawValue)
        
        locationStorageManager.deleteAllData()
        
        XCTAssertNil(userDefaults.data(forKey: LocationStorageManager.StorageKey.lastLocation.rawValue))
    }
}
