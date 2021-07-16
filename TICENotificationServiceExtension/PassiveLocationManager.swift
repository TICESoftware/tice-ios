//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels
import CoreLocation

enum PassiveLocationManagerError: LocalizedError {
    case notAvailable

    var errorDescription: String? {
        switch self {
        case .notAvailable: return "Operation not available in passive location manager."
        }
    }
}

class PassiveLocationManager: LocationManagerType {
    weak var delegate: LocationManagerDelegate?

    var monitoringGroups: Set<GroupId>
    var lastUserLocation: Location?
    var authorizationStatus: LocationAuthorizationStatus
    var notAuthorizedToUseLocation: Bool
    var currentUserLocation: Location? { lastUserLocation }

    init(locationStorageManager: LocationStorageManagerType) {
        self.monitoringGroups = Set()
        self.authorizationStatus = .notAuthorized
        self.notAuthorizedToUseLocation = true

        do {
            self.lastUserLocation = try locationStorageManager.loadLastLocation()
        } catch {
            logger.error("Error loading last location.")
            self.lastUserLocation = nil
        }
    }
    
    func registerHandler() {}
    
    func setup() {
    }

    func requestLocationAuthorization() {
        logger.error("Operation not available in passive location manager.")
    }

    func lastLocation(userId: UserId, groupId: GroupId) -> Location? {
        return lastUserLocation
    }

    func startLocationMonitoring(in meetup: Meetup) throws {
        throw PassiveLocationManagerError.notAvailable
    }

    func stopLocationMonitoring(in groupId: GroupId) {
        logger.error("Operation not available in passive location manager.")
    }

    func stopLocationMonitoringForAllGroups() {
        logger.error("Operation not available in passive location manager.")
    }
    
    func locationSharingState(userId: UserId, groupId: GroupId) -> LocationSharingState {
        return LocationSharingState(userId: userId, groupId: groupId, enabled: !monitoringGroups.isEmpty, lastUpdated: Date())
    }
    
    func othersLocationSharingState(ownUserId: UserId, groupId: GroupId) -> [LocationSharingState] {
        return []
    }
}
