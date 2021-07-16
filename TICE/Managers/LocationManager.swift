//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import CoreLocation
import TICEAPIModels
import PromiseKit

protocol LocationAuthorizationStatusChangeHandler {
    func authorizationStatusChanged(to status: LocationAuthorizationStatus)
}

protocol UserLocationUpdateNotificationHandler {
    func didUpdateLocation(userId: UserId)
}

protocol LocationManagerDelegate: AnyObject {
    func processLocationUpdate(location: Location)
}

enum LocationManagerError: LocalizedError {
    case servicesUnavailable
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .servicesUnavailable: return "Location services not available."
        case .notAuthorized: return "App is not authorized to use location services."
        }
    }
}

enum LocationAuthorizationStatus {
    case notDetermined
    case notAuthorized
    case authorized

    init(clAuthorizationStatus: CLAuthorizationStatus) {
        switch clAuthorizationStatus {
        case .notDetermined:
            self = .notDetermined
        case .restricted, .denied:
            self = .notAuthorized
        case .authorizedWhenInUse, .authorizedAlways:
            self = .authorized
        @unknown default:
            logger.error("Unknown authorization status: \(clAuthorizationStatus)")
            fatalError()
        }
    }
}

class LocationManager: NSObject, LocationManagerType {
    let userManager: UserManagerType
    weak var postOffice: PostOfficeType?
    let locationStorageManager: LocationStorageManagerType
    let notifier: Notifier
    let tracker: TrackerType
    let signedInUser: SignedInUser
    
    let clLocationManager: CLLocationManagerType

    weak var delegate: LocationManagerDelegate?

    var lastUserLocation: Location? {
        didSet {
            do {
                try locationStorageManager.store(lastLocation: lastUserLocation)
            } catch {
                logger.error("Failed to save last location.")
            }
        }
    }
    
    var currentUserLocation: Location? { clLocationManager.location?.location ?? lastUserLocation }
    var currentMovingType: MovingType

    let locationResendTimeout: TimeInterval
    let locationMaxAge: TimeInterval
    var refreshBroadcastTimer: Timer?
    
    private var locationRequirementObserverToken: ObserverToken?

    init(clLocationManager: CLLocationManagerType, locationStorageManager: LocationStorageManagerType, userManager: UserManagerType, postOffice: PostOfficeType, notifier: Notifier, tracker: TrackerType, signedInUser: SignedInUser, locationResendTimeout: TimeInterval, locationMaxAge: TimeInterval) {
        self.clLocationManager = clLocationManager
        self.locationStorageManager = locationStorageManager
        self.currentMovingType = .walking

        self.userManager = userManager
        self.postOffice = postOffice
        self.notifier = notifier
        self.tracker = tracker
        self.signedInUser = signedInUser
        
        self.locationResendTimeout = locationResendTimeout
        self.locationMaxAge = locationMaxAge

        super.init()
    }
    
    deinit {
        locationRequirementObserverToken = nil
        self.postOffice?.handlers[.locationUpdateV2] = nil
        self.refreshBroadcastTimer?.invalidate()
    }
    
    func setup() {
        self.clLocationManager.delegate = self
        self.clLocationManager.allowsBackgroundLocationUpdates = true
        self.clLocationManager.desiredAccuracy = kCLLocationAccuracyBest
        self.clLocationManager.distanceFilter = currentMovingType.distanceFilter
        
        locationRequirementObserverToken = locationStorageManager.observeLocationRequirement(userId: signedInUser.userId, queue: .global()) { [weak self] locationRequirement in
            if locationRequirement {
                do { try self?.resumeLocationMonitoring() } catch { logger.error("Unable to start location monitoring: \(error)") }
            } else {
                self?.pauseLocationMonitoring()
            }
        }
    }

    enum MovingType {
        case unknown
        case walking
        case running
        case cycling
        case car
        case train
        case plane
        case rocket

        init(speed: CLLocationSpeed) {
            switch Int(speed) {
            case ..<0: self = .unknown
            case 0...2: self = .walking
            case 3...6: self = .running
            case 7...9: self = .cycling
            case 10...30: self = .car
            case 31...56: self = .train
            case 57...300: self = .plane
            case 301...: self = .rocket
            default: self = .unknown
            }
        }

        var distanceFilter: CLLocationDistance {
            switch self {
            case .unknown: return 5.0
            case .walking: return 5.0
            case .running: return 10.0
            case .cycling: return 20.0
            case .car: return 100.0
            case .train: return 500.0
            case .plane: return 1_000.0
            case .rocket: return 5_000.0
            }
        }
    }

    var authorizationStatus: LocationAuthorizationStatus {
        return LocationAuthorizationStatus(clAuthorizationStatus: clLocationManager.authorizationStatus())
    }

    var notAuthorizedToUseLocation: Bool {
        return authorizationStatus == .notAuthorized
    }
    
    private var locationMonitoringRequired: Bool {
        do { return try locationStorageManager.locationRequired(userId: signedInUser.userId) } catch {
            logger.error("Error determing requirement to track location.")
            return false
        }
    }
    
    private func startLocationMonitoringIfNecessary() throws {
        if try locationStorageManager.locationRequired(userId: signedInUser.userId) {
            try resumeLocationMonitoring()
        }
    }

    func requestLocationAuthorization() {
        guard authorizationStatus == .notDetermined else {
            logger.warning("Not requesting location authorization because the user already decided: \(authorizationStatus)")
            return
        }

        logger.info("Authorization status is not determined. Requesting authorization from user.")
        clLocationManager.requestWhenInUseAuthorization()
    }

    private func pauseLocationMonitoring() {
        logger.info("Pause location monitoring")
        DispatchQueue.main.async { [weak self] in self?.refreshBroadcastTimer?.invalidate() }
        clLocationManager.stopUpdatingLocation()
    }

    private func resumeLocationMonitoring() throws {
        guard clLocationManager.locationServicesEnabled() else {
            throw LocationManagerError.servicesUnavailable
        }

        switch authorizationStatus {
        case .notDetermined:
            requestLocationAuthorization()
        case .notAuthorized:
            throw LocationManagerError.notAuthorized
        case .authorized:
            logger.debug("Resume location monitoring.")
            clLocationManager.startUpdatingLocation()

            resetRefreshBroadcastTimer()
        }
    }

    private func adjustDistanceFilter(speed: CLLocationSpeed) {
        let newMovingType = MovingType(speed: speed)

        if newMovingType != currentMovingType {
            clLocationManager.distanceFilter = newMovingType.distanceFilter

            logger.debug("DistanceFilter: \(currentMovingType.distanceFilter) -> \(newMovingType.distanceFilter)")

            currentMovingType = newMovingType
        }
    }

    private func resetRefreshBroadcastTimer() {
        DispatchQueue.main.async {
            self.refreshBroadcastTimer?.invalidate()
            self.refreshBroadcastTimer = Timer.scheduledTimer(withTimeInterval: self.locationResendTimeout, repeats: true, block: { [unowned self] _ in
                guard self.locationMonitoringRequired else {
                    logger.info("Location monitoring no longer required. Pausing monitoring.")
                    self.pauseLocationMonitoring()
                    return
                }
                
                logger.debug("Location hasn't changed in a while. Send last available location as update.")
                if let lastLocation = self.lastUserLocation {
                    var updatedLocation = lastLocation
                    updatedLocation.timestamp = Date()
                    self.delegate?.processLocationUpdate(location: updatedLocation)
                } else {
                    logger.debug("No last location available.")
                }
            })
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        logger.debug("Location services authorization status changed to \(status.rawValue).")
        tracker.log(action: .locationAuthorization, category: .app, detail: "\(status.rawValue)")

        let authorizationStatus = LocationAuthorizationStatus(clAuthorizationStatus: status)
        switch authorizationStatus {
        case .notDetermined:
            logger.info("Location services authorization reset. Not determined for now.")
            pauseLocationMonitoring()
        case .notAuthorized:
            logger.info("Location services authorization revoked. Stopping location updates for all groups.")
            pauseLocationMonitoring()
        case .authorized:
            logger.info("Location services authorization granted. Starting location updates for monitored groups.")
            do {
                try startLocationMonitoringIfNecessary()
            } catch {
                logger.error("Unable to start location monitoring: \(error)")
            }
        }

        notifier.notify(LocationAuthorizationStatusChangeHandler.self) { $0.authorizationStatusChanged(to: authorizationStatus) }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        logger.debug("Got location updates from system")
        
        guard locationMonitoringRequired else {
            logger.info("Location monitoring no longer required. Pausing monitoring.")
            pauseLocationMonitoring()
            return
        }
        
        guard let location = locations.last?.location else {
            logger.warning("Location update was empty")
            return
        }
        lastUserLocation = location
        delegate?.processLocationUpdate(location: location)
        resetRefreshBroadcastTimer()
        adjustDistanceFilter(speed: location.speed ?? -1)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        logger.error("Did fail to get location updates from system with error: \(error)")
    }
}
