//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import CoreLocation
import TICEAPIModels
import GRDB

class LocationStorageManager: LocationStorageManagerType {

    enum StorageKey: String {
        case lastLocation
    }

    let userDefaults: UserDefaults
    let encoder: JSONEncoder
    let decoder: JSONDecoder
    let database: DatabaseWriter

    init(userDefaults: UserDefaults, encoder: JSONEncoder, decoder: JSONDecoder, database: DatabaseWriter) {
        self.userDefaults = userDefaults
        self.encoder = encoder
        self.decoder = decoder
        self.database = database
    }

    func store(lastLocation: Location?) throws {
        if let lastLocation = lastLocation {
            let locationData = try encoder.encode(lastLocation)
            userDefaults.set(locationData, forKey: StorageKey.lastLocation.rawValue)
        } else {
            userDefaults.removeObject(forKey: StorageKey.lastLocation.rawValue)
        }
    }

    func loadLastLocation() throws -> Location? {
        try userDefaults.data(forKey: StorageKey.lastLocation.rawValue).map { locationData in
            return try decoder.decode(Location.self, from: locationData)
        }
    }
    
    func observeLocationRequirement(userId: UserId, queue: DispatchQueue, onChange: @escaping (Bool) -> Void) -> ObserverToken {
        database.observe({ try self.locationRequired(userId: userId, db: $0) }, queue: queue, onChange: onChange)
    }
    
    func locationRequired(userId: UserId) throws -> Bool {
        try database.read { try locationRequired(userId: userId, db: $0) }
    }
    
    private func locationRequired(userId: UserId, db: Database) throws -> Bool {
        return try LocationSharingState
            .filter(LocationSharingState.Columns.userId == userId)
            .filter(LocationSharingState.Columns.enabled == true)
            .fetchCount(db) > 0
    }
    
    func observeLocationSharingState(queue: DispatchQueue, onChange: @escaping ([LocationSharingState]) -> Void) -> ObserverToken {
        database.observe({ db in try LocationSharingState.fetchAll(db) }, queue: queue, onChange: onChange)
    }
    
    func observeLocationSharingState(userId: UserId, groupId: GroupId, queue: DispatchQueue = .main, onChange: @escaping (LocationSharingState?) -> Void) -> ObserverToken {
        let fetch = { db in
            try LocationSharingState.fetchOne(db,
                                              key: [LocationSharingState.Columns.userId.name: userId,
                                                    LocationSharingState.Columns.groupId.name: groupId])
        }
        return database.observe(fetch, queue: queue, onChange: onChange)
    }
    
    func locationSharingStates() throws -> [LocationSharingState] {
        try database.read { db in
            try LocationSharingState.fetchAll(db)
        }
    }
    
    func locationSharingStates(withEnabledState enabled: Bool) throws -> [LocationSharingState] {
        try database.read { db in
            try LocationSharingState.filter(LocationSharingState.Columns.enabled == enabled).fetchAll(db)
        }
    }
    
    func locationSharingState(userId: UserId) throws -> [LocationSharingState] {
        try database.read { db in
            try LocationSharingState.filter(LocationSharingState.Columns.userId == userId).fetchAll(db)
        }
    }
    
    func locationSharingState(userId: UserId, groupId: GroupId) throws -> LocationSharingState? {
        try database.read { db in
            try LocationSharingState.fetchOne(db, key: [LocationSharingState.Columns.userId.name: userId,
                                                        LocationSharingState.Columns.groupId.name: groupId])
        }
    }
    
    func observeLocationSharingState(groupId: GroupId, queue: DispatchQueue = .main, onChange: @escaping ([LocationSharingState]) -> Void) -> ObserverToken {
        let fetch = { db in
            try LocationSharingState
                .filter(LocationSharingState.Columns.groupId == groupId)
                .fetchAll(db)
        }
        return database.observe(fetch, queue: queue, onChange: onChange)
    }
    
    func observeOthersLocationSharingState(ownUserId: UserId, groupId: GroupId, queue: DispatchQueue = .main, onChange: @escaping ([LocationSharingState]) -> Void) -> ObserverToken {
        let fetch = { db in
            try LocationSharingState
                .filter(LocationSharingState.Columns.groupId == groupId)
                .filter(LocationSharingState.Columns.userId != ownUserId)
                .fetchAll(db)
        }
        return database.observe(fetch, queue: queue, onChange: onChange)
    }
    
    func othersLocationSharingState(ownUserId: UserId, groupId: GroupId) throws -> [LocationSharingState] {
        try database.read { db in
            try LocationSharingState
                .filter(LocationSharingState.Columns.groupId == groupId)
                .filter(LocationSharingState.Columns.userId != ownUserId)
                .fetchAll(db)
        }
    }
    
    func storeLocationSharingState(userId: UserId, groupId: GroupId, enabled: Bool, lastUpdated: Date) throws {
        return try database.write { db in
            let state = LocationSharingState(userId: userId,
                                             groupId: groupId,
                                             enabled: enabled,
                                             lastUpdated: lastUpdated)
            try state.save(db)
        }
    }
}

extension LocationStorageManager: DeletableStorageManagerType {
    func deleteAllData() {
        userDefaults.removeObject(forKey: StorageKey.lastLocation.rawValue)
    }
}
