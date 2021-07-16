//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import XCTest
import TICEAPIModels
import CoreLocation
import PromiseKit
import Shouter
import Cuckoo
import GRDB

@testable import TICE

class LocationManagerTests: XCTestCase {

    var clLocationManager: MockCLLocationManagerType!
    var locationStorageManager: MockLocationStorageManagerType!
    var userManager: MockUserManagerType!
    var postOffice: MockPostOfficeType!
    var notifier: Notifier!
    var signedInUser: SignedInUser!

    var locationManager: LocationManager!

    var didChangeAuthorizationStatus: ((LocationAuthorizationStatus) -> Void)?
    var processLocationUpdate: ((Location) -> Void)?
    
    var onLocationRequirementChangeHandler: ((Bool) -> Void)?

    override func setUp() {
        super.setUp()
        
        clLocationManager = MockCLLocationManagerType()
        locationStorageManager = MockLocationStorageManagerType()
        userManager = MockUserManagerType()
        postOffice = MockPostOfficeType()
        notifier = Shouter()
        
        signedInUser = SignedInUser(userId: UserId(), privateSigningKey: Data(), publicSigningKey: Data(), publicName: nil)

        locationManager = LocationManager(clLocationManager: clLocationManager, locationStorageManager: locationStorageManager, userManager: userManager, postOffice: postOffice, notifier: notifier, tracker: MockTracker(), signedInUser: signedInUser, locationResendTimeout: 2.0, locationMaxAge: 60.0)
        
        stub(postOffice) { stub in
            when(stub.handlers.get).thenReturn([:])
            when(stub.handlers.set(any())).thenDoNothing()
        }
        
        stub(locationStorageManager) { stub in
            when(stub.locationRequired(userId: any())).thenReturn(false)
        }
        
        stub(clLocationManager) { stub in
            when(stub.stopUpdatingLocation()).thenDoNothing()
        }
    }

    override func tearDown() {
        notifier.unregister(LocationAuthorizationStatusChangeHandler.self, observer: self)

        didChangeAuthorizationStatus = nil
        processLocationUpdate = nil

        onLocationRequirementChangeHandler = nil
        
        locationManager = nil

        super.tearDown()
    }
    
    private func setupLocationManager() {
        stub(clLocationManager) { stub in
            when(stub.delegate.set(any())).thenDoNothing()
            when(stub.allowsBackgroundLocationUpdates.set(true)).thenDoNothing()
            when(stub.desiredAccuracy.set(kCLLocationAccuracyBest)).thenDoNothing()
            when(stub.distanceFilter.set(LocationManager.MovingType.walking.distanceFilter)).thenDoNothing()
        }
        
        stub(locationStorageManager) { stub in
            when(stub.observeLocationRequirement(userId: signedInUser.userId, queue: any(), onChange: any())).then { [unowned self] _, _, handler in
                self.onLocationRequirementChangeHandler = handler
                return MockObserverToken()
            }
        }
        
        locationManager.setup()
    }

    func testSetup() {
        setupLocationManager()
        
        verify(clLocationManager).delegate.set(any())
        verify(clLocationManager).allowsBackgroundLocationUpdates.set(true)
        verify(clLocationManager).desiredAccuracy.set(kCLLocationAccuracyBest)
        verify(clLocationManager).distanceFilter.set(LocationManager.MovingType.walking.distanceFilter)
    }

    func testAuthorizationChecks() {
        stub(clLocationManager) { stub in
            when(stub.authorizationStatus()).thenReturn(.authorizedAlways, .authorizedWhenInUse, .denied, .restricted, .notDetermined)
        }
        
        XCTAssertEqual(locationManager.authorizationStatus, .authorized)
        XCTAssertEqual(locationManager.authorizationStatus, .authorized)
        XCTAssertEqual(locationManager.authorizationStatus, .notAuthorized)
        XCTAssertEqual(locationManager.authorizationStatus, .notAuthorized)
        XCTAssertEqual(locationManager.authorizationStatus, .notDetermined)
    }
    
    func testNotAuthorizedToUseLocation() {
        stub(clLocationManager) { stub in
            when(stub.authorizationStatus()).thenReturn(.authorizedAlways, .authorizedWhenInUse, .denied, .restricted, .notDetermined)
        }
        
        XCTAssertFalse(locationManager.notAuthorizedToUseLocation)
        XCTAssertFalse(locationManager.notAuthorizedToUseLocation)
        XCTAssertTrue(locationManager.notAuthorizedToUseLocation)
        XCTAssertTrue(locationManager.notAuthorizedToUseLocation)
        XCTAssertFalse(locationManager.notAuthorizedToUseLocation)
    }

    func testRequestingLocationAuthorization() {
        stub(clLocationManager) { stub in
            when(stub.authorizationStatus()).thenReturn(.notDetermined, .authorizedAlways, .authorizedWhenInUse, .denied, .restricted)
            when(stub.requestWhenInUseAuthorization()).thenDoNothing()
        }
        
        locationManager.requestLocationAuthorization()
        
        verify(clLocationManager).requestWhenInUseAuthorization()
        
        locationManager.requestLocationAuthorization()
        locationManager.requestLocationAuthorization()
        locationManager.requestLocationAuthorization()
        locationManager.requestLocationAuthorization()
        
        verify(clLocationManager, times(1)).requestWhenInUseAuthorization()
    }
    
    func testStopLocationMonitoring() {
        setupLocationManager()
        
        stub(clLocationManager) { stub in
            when(stub.stopUpdatingLocation()).thenDoNothing()
        }
        
        onLocationRequirementChangeHandler?(false)
        
        verify(clLocationManager).stopUpdatingLocation()
    }

    func testStartLocationMonitoringServicesNotAvailable() throws {
        setupLocationManager()
        
        stub(clLocationManager) { stub in
            when(stub.locationServicesEnabled()).thenReturn(false)
        }
        
        onLocationRequirementChangeHandler?(true)
    }

    func testStartLocationMonitoringAuthorizationNotDetermined() throws {
        setupLocationManager()
        
        stub(clLocationManager) { stub in
            when(stub.locationServicesEnabled()).thenReturn(true)
            when(stub.authorizationStatus()).thenReturn(.notDetermined)
            when(stub.requestWhenInUseAuthorization()).thenDoNothing()
        }
        
        onLocationRequirementChangeHandler?(true)
        
        verify(clLocationManager, times(2)).authorizationStatus()
        verify(clLocationManager).requestWhenInUseAuthorization()
    }

    func testStartLocationMonitoringNotAuthorized() throws {
        setupLocationManager()
        
        stub(clLocationManager) { stub in
            when(stub.locationServicesEnabled()).thenReturn(true)
            when(stub.authorizationStatus()).thenReturn(.denied)
        }
        
        onLocationRequirementChangeHandler?(true)
        
        verify(clLocationManager).authorizationStatus()
    }
    
    func testStartLocationMonitoringAuthorized() throws {
        setupLocationManager()
        
        stub(clLocationManager) { stub in
            when(stub.locationServicesEnabled()).thenReturn(true)
            when(stub.authorizationStatus()).thenReturn(.authorizedWhenInUse)
            when(stub.startUpdatingLocation()).thenDoNothing()
        }
        
        onLocationRequirementChangeHandler?(true)
        
        verify(clLocationManager).authorizationStatus()
        verify(clLocationManager).startUpdatingLocation()
    }
    
    func testAuthorizationChanged() {
        setupLocationManager()
        
        stub(clLocationManager) { stub in
            when(stub.stopUpdatingLocation()).thenDoNothing()
        }
        
        locationManager.locationManager(CLLocationManager(), didChangeAuthorization: .notDetermined)
        verify(clLocationManager, times(1)).stopUpdatingLocation()
        
        locationManager.locationManager(CLLocationManager(), didChangeAuthorization: .denied)
        verify(clLocationManager, times(2)).stopUpdatingLocation()
        
        locationManager.locationManager(CLLocationManager(), didChangeAuthorization: .restricted)
        verify(clLocationManager, times(3)).stopUpdatingLocation()
        
        stub(locationStorageManager) { stub in
            when(stub.locationRequired(userId: signedInUser.userId)).thenReturn(false, true)
        }
        
        locationManager.locationManager(CLLocationManager(), didChangeAuthorization: .authorizedWhenInUse)
        verify(clLocationManager, never()).startUpdatingLocation()
        
        stub(clLocationManager) { stub in
            when(stub.locationServicesEnabled()).thenReturn(true)
            when(stub.authorizationStatus()).thenReturn(.authorizedWhenInUse)
            when(stub.startUpdatingLocation()).thenDoNothing()
        }
        
        locationManager.locationManager(CLLocationManager(), didChangeAuthorization: .authorizedWhenInUse)
        verify(clLocationManager).startUpdatingLocation()
    }

    func testReceiveUserLocationUpdate() {
        let userLocation = CLLocation(latitude: 52.0, longitude: 13.0)

        locationManager.delegate = self
        let calledLocationProcessing = expectation(description: "Called location processing")
        processLocationUpdate = { location in
            XCTAssertEqual(location.latitude, userLocation.location.latitude, "Invalid location")
            calledLocationProcessing.fulfill()
        }
        
        stub(clLocationManager) { stub in
            when(stub.distanceFilter.set(LocationManager.MovingType.walking.distanceFilter)).thenDoNothing()
        }
        
        stub(locationStorageManager) { stub in
            when(stub.store(lastLocation: userLocation.location)).thenDoNothing()
            when(stub.locationRequired(userId: signedInUser.userId)).thenReturn(true)
        }

        locationManager.locationManager(CLLocationManager(), didUpdateLocations: [userLocation])

        XCTAssertEqual(locationManager.lastUserLocation?.latitude, userLocation.location.latitude, "Invalid location")

        wait(for: [calledLocationProcessing])
    }
    
    func testReceiveUserLocationMonitoringNotRequired() {
        let userLocation = CLLocation(latitude: 52.0, longitude: 13.0)
        
        stub(clLocationManager) { stub in
            when(stub.stopUpdatingLocation()).thenDoNothing()
        }
        
        stub(locationStorageManager) { stub in
            when(stub.locationRequired(userId: signedInUser.userId)).thenReturn(false)
        }

        locationManager.locationManager(CLLocationManager(), didUpdateLocations: [userLocation])
        
        verify(clLocationManager).stopUpdatingLocation()
    }

    func testAdjustingDistanceFilter() {
        stub(locationStorageManager) { stub in
            when(stub.store(lastLocation: any())).thenDoNothing()
            when(stub.locationRequired(userId: signedInUser.userId)).thenReturn(true)
        }
        
        // current moving type already set to walking
        let walkingLocation = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 52.0, longitude: 13.0), altitude: 0.0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, course: 0.0, speed: 2.0, timestamp: Date())
        locationManager.locationManager(CLLocationManager(), didUpdateLocations: [walkingLocation])
        verify(clLocationManager, never()).distanceFilter.set(any())
        
        locationManager.currentMovingType = .unknown
        
        stub(clLocationManager) { when($0.distanceFilter.set(5.0)).thenDoNothing() }
        locationManager.locationManager(CLLocationManager(), didUpdateLocations: [walkingLocation])
        verify(clLocationManager).distanceFilter.set(5.0)

        let runningLocation = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 52.0, longitude: 13.0), altitude: 0.0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, course: 0.0, speed: 6.0, timestamp: Date())
        stub(clLocationManager) { when($0.distanceFilter.set(10.0)).thenDoNothing() }
        locationManager.locationManager(CLLocationManager(), didUpdateLocations: [runningLocation])
        verify(clLocationManager).distanceFilter.set(10.0)

        let cyclingLocation = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 52.0, longitude: 13.0), altitude: 0.0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, course: 0.0, speed: 9.0, timestamp: Date())
        stub(clLocationManager) { when($0.distanceFilter.set(20.0)).thenDoNothing() }
        locationManager.locationManager(CLLocationManager(), didUpdateLocations: [cyclingLocation])
        verify(clLocationManager).distanceFilter.set(20.0)

        let carLocation = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 52.0, longitude: 13.0), altitude: 0.0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, course: 0.0, speed: 30.0, timestamp: Date())
        stub(clLocationManager) { when($0.distanceFilter.set(100.0)).thenDoNothing() }
        locationManager.locationManager(CLLocationManager(), didUpdateLocations: [carLocation])
        verify(clLocationManager).distanceFilter.set(100.0)

        let trainLocation = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 52.0, longitude: 13.0), altitude: 0.0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, course: 0.0, speed: 56.0, timestamp: Date())
        stub(clLocationManager) { when($0.distanceFilter.set(500.0)).thenDoNothing() }
        locationManager.locationManager(CLLocationManager(), didUpdateLocations: [trainLocation])
        verify(clLocationManager).distanceFilter.set(500.0)

        let planeLocation = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 52.0, longitude: 13.0), altitude: 0.0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, course: 0.0, speed: 300.0, timestamp: Date())
        stub(clLocationManager) { when($0.distanceFilter.set(1_000.0)).thenDoNothing() }
        locationManager.locationManager(CLLocationManager(), didUpdateLocations: [planeLocation])
        verify(clLocationManager).distanceFilter.set(1_000.0)

        let insaneSpeedLocation = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 52.0, longitude: 13.0), altitude: 0.0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, course: 0.0, speed: 301.0, timestamp: Date())
        stub(clLocationManager) { when($0.distanceFilter.set(5_000.0)).thenDoNothing() }
        locationManager.locationManager(CLLocationManager(), didUpdateLocations: [insaneSpeedLocation])
        verify(clLocationManager).distanceFilter.set(5_000.0)
    }

    func testBroadcastTimer() throws {
        let lastLocation = Location(latitude: 52.0, longitude: 13.0)
        
        stub(locationStorageManager) { stub in
            when(stub.store(lastLocation: lastLocation)).thenDoNothing()
            when(stub.locationRequired(userId: signedInUser.userId)).thenReturn(true)
        }
        
        locationManager.lastUserLocation = lastLocation
        locationManager.delegate = self

        let firstLocationUpdate = expectation(description: "First location update")
        let secondLocationUpdate = expectation(description: "Second location update")
        secondLocationUpdate.isInverted = true
        var firstUpdate = true
        processLocationUpdate = { location in
            XCTAssertEqual(location.latitude, lastLocation.latitude, "Invalid location")

            if firstUpdate {
                firstLocationUpdate.fulfill()
                firstUpdate = false
            } else {
                secondLocationUpdate.fulfill()
            }
        }
        
        stub(clLocationManager) { stub in
            when(stub.locationServicesEnabled()).thenReturn(true)
            when(stub.authorizationStatus()).thenReturn(.authorizedWhenInUse)
            when(stub.startUpdatingLocation()).thenDoNothing()
            when(stub.stopUpdatingLocation()).thenDoNothing()
        }
        
        setupLocationManager()
        onLocationRequirementChangeHandler?(true)

        wait(for: [firstLocationUpdate])
        
        onLocationRequirementChangeHandler?(false)
        
        wait(for: [secondLocationUpdate])
    }
}

extension LocationManagerTests: LocationAuthorizationStatusChangeHandler {
    func authorizationStatusChanged(to status: LocationAuthorizationStatus) {
        didChangeAuthorizationStatus?(status)
    }
}

extension LocationManagerTests: LocationManagerDelegate {
    func processLocationUpdate(location: Location) {
        processLocationUpdate?(location)
    }
}

