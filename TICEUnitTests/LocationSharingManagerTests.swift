//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import XCTest
import TICEAPIModels
import PromiseKit
import Cuckoo
import Shouter
import CoreLocation

@testable import TICE

class LocationSharingManagerTests: XCTestCase {
    
    var locationStorageManager: MockLocationStorageManagerType!
    var groupManager: MockGroupManagerType!
    var groupStorageManager: MockGroupStorageManagerType!
    var postOffice: MockPostOfficeType!
    var userManager: MockUserManagerType!
    var signedInUser: SignedInUser!
    var notifier: Notifier!
    
    var locationSharingManager: LocationSharingManager!
    
    var didUpdateLocationCallback: ((UserId) -> Void)?
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        locationStorageManager = mock(MockLocationStorageManagerType.init)
        groupManager = mock(MockGroupManagerType.init)
        groupStorageManager = mock(MockGroupStorageManagerType.init)
        userManager = mock(MockUserManagerType.init)
        postOffice = mock(MockPostOfficeType.init)
        notifier = Shouter()
        
        let signingKeyPair = KeyPair(privateKey: Data(), publicKey: Data())
        signedInUser = SignedInUser(userId: UserId(), privateSigningKey: signingKeyPair.privateKey, publicSigningKey: signingKeyPair.publicKey, publicName: nil)
        
        locationSharingManager = LocationSharingManager(locationStorageManager: locationStorageManager, groupManager: groupManager, groupStorageManager: groupStorageManager, userManager: userManager, signedInUser: signedInUser, postOffice: postOffice, notifier: notifier, checkTime: 3.0, locationMaxAge: 2.0)
        
        stub(postOffice) { stub in
            when(stub.handlers.get).thenReturn([:])
            when(stub.handlers.set(any())).thenDoNothing()
        }
    }
    
    override func tearDownWithError() throws {
        notifier.unregister(UserLocationUpdateNotificationHandler.self, observer: self)
        didUpdateLocationCallback = nil
        
        locationSharingManager = nil
        
        try super.tearDownWithError()
    }
    
    func testLocationUpdateFromFutureHandling() {
        let user = User(userId: UserId(), publicSigningKey: Data(), publicName: nil)
        let groupId = GroupId()
        
        stub(userManager) { stub in
            when(stub.user(user.userId)).thenReturn(user)
        }
        stub(locationStorageManager) { stub in
            when(stub.locationSharingState(userId: user.userId, groupId: groupId)).thenReturn(LocationSharingState(userId: user.userId, groupId: groupId, enabled: true, lastUpdated: Date()))
        }
        stub(groupStorageManager) { stub in
            when(stub.isMember(userId: user.userId, groupId: groupId)).thenReturn(true)
        }
        
        let location = Location(latitude: 42.0, longitude: 1337.0, altitude: 4711.0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: Date() + 60)
        let locationUpdate = LocationUpdateV2(location: location, groupId: groupId)
        let payloadMetaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: user.userId, timestamp: Date(), collapseId: nil, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, conversationInvitation: nil)
        
        let handlerCalled = expectation(description: "Completion")
        locationSharingManager.handleLocationUpdate(payload: locationUpdate, metaInfo: payloadMetaInfo) { result in
            defer { handlerCalled.fulfill() }
            
            guard let lastLocation = self.locationSharingManager.lastLocation(userId: user.userId, groupId: groupId) else {
                XCTFail("No last location existing")
                return
            }
            
            XCTAssertLessThanOrEqual(lastLocation.timestamp, Date(), "Incorrect timestamp")
        }
        
        wait(for: [handlerCalled])
    }
    
    func testLocationUpdateHandling() {
        let handlerCalled = expectation(description: "Completion")
        let didUpdateLocationNotification = expectation(description: "User update called")
        
        let groupId = GroupId()
        let user = User(userId: UserId(), publicSigningKey: Data(), publicName: nil)
        stub(userManager) { stub in
            when(stub.user(user.userId)).thenReturn(user)
        }
        stub(locationStorageManager) { stub in
            when(stub.locationSharingState(userId: user.userId, groupId: groupId)).thenReturn(LocationSharingState(userId: user.userId, groupId: groupId, enabled: true, lastUpdated: Date()))
        }
        stub(groupStorageManager) { stub in
            when(stub.isMember(userId: user.userId, groupId: groupId)).thenReturn(true)
        }
        
        notifier.register(UserLocationUpdateNotificationHandler.self, observer: self)
        didUpdateLocationCallback = { userId in
            defer { didUpdateLocationNotification.fulfill() }
            XCTAssertEqual(userId, user.userId, "Invalid callback")
        }
        
        let location = Location(latitude: 42.0, longitude: 1337.0, altitude: 4711.0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: Date())
        let locationUpdate = LocationUpdateV2(location: location, groupId: groupId)
        let payloadMetaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: user.userId, timestamp: Date(), collapseId: nil, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, conversationInvitation: nil)
        
        locationSharingManager.handleLocationUpdate(payload: locationUpdate, metaInfo: payloadMetaInfo) { result in
            defer { handlerCalled.fulfill() }
            
            guard let lastLocation = self.locationSharingManager.lastLocation(userId: user.userId, groupId: groupId) else {
                XCTFail("No last location existing")
                return
            }
            
            XCTAssertEqual(lastLocation.coordinate.latitude, locationUpdate.location.latitude, "Incorrect location")
            XCTAssertEqual(lastLocation.coordinate.longitude, locationUpdate.location.longitude, "Incorrect location")
            XCTAssertEqual(lastLocation.altitude, locationUpdate.location.altitude, "Incorrect location")
            XCTAssertEqual(lastLocation.horizontalAccuracy, locationUpdate.location.horizontalAccuracy, "Incorrect location")
            XCTAssertEqual(lastLocation.verticalAccuracy, locationUpdate.location.verticalAccuracy, "Incorrect location")
            XCTAssertGreaterThan(lastLocation.timestamp, Date().addingTimeInterval(-5.0), "Incorrect location")
            XCTAssertLessThan(lastLocation.timestamp, Date(), "Incorrect location")
        }
        
        wait(for: [handlerCalled, didUpdateLocationNotification])
    }
    
    func testLocationUpdateHandlingUnknownUser() {
        let handlerCalled = expectation(description: "Completion")
        
        let user = User(userId: UserId(), publicSigningKey: Data(), publicName: nil)
        stub(userManager) { stub in
            when(stub.user(user.userId)).thenReturn(nil)
        }
        
        let location = Location(latitude: 42.0, longitude: 1337.0, altitude: 4711.0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: Date())
        let locationUpdate = LocationUpdate(location: location)
        let payloadMetaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: user.userId, timestamp: Date(), collapseId: nil, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, conversationInvitation: nil)
        
        locationSharingManager.handleLocationUpdate(payload: locationUpdate, metaInfo: payloadMetaInfo) { result in
            XCTAssertEqual(result, .failed, "Invalid result")
            handlerCalled.fulfill()
        }
        
        wait(for: [handlerCalled])
    }
    
    func testHandleLocationUpdateFromUserNotInGroup() {
        let userId = UserId()
        let groupId = GroupId()
        
        let handlerCalled = expectation(description: "Completion")
        
        let user = User(userId: userId, publicSigningKey: Data(), publicName: nil)
        stub(userManager) { stub in
            when(stub.user(user.userId)).thenReturn(user)
        }
        stub(locationStorageManager) { stub in
            when(stub.locationSharingState(userId: user.userId, groupId: groupId)).thenReturn(nil)
        }
        stub(groupStorageManager) { stub in
            when(stub.isMember(userId: user.userId, groupId: groupId)).thenReturn(false)
        }
        
        notifier.register(UserLocationUpdateNotificationHandler.self, observer: self)
        
        let location = Location(latitude: 42.0, longitude: 1337.0, altitude: 4711.0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: Date())
        let locationUpdate = LocationUpdateV2(location: location, groupId: groupId)
        let payloadMetaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: user.userId, timestamp: Date(), collapseId: nil, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, conversationInvitation: nil)
        
        locationSharingManager.handleLocationUpdate(payload: locationUpdate, metaInfo: payloadMetaInfo) { result in
            defer { handlerCalled.fulfill() }
            
            let lastLocation = self.locationSharingManager.lastLocation(userId: user.userId, groupId: groupId)
            XCTAssertNil(lastLocation, "Updated location but user is not in group")
        }
        
        wait(for: [handlerCalled])
    }
    
    func testHandleNewLocationUpdate() {
        let userId = UserId()
        let groupId = GroupId()
        let key = LocationSharingManager.UserGroupIds(userId: userId, groupId: groupId)
        
        let oldLocation = Location(coordinate: CLLocationCoordinate2D(), altitude: 13.0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: Date().addingTimeInterval(-10.0))
        locationSharingManager.lastLocations = [key: oldLocation]
        
        let handlerCalled = expectation(description: "Completion")
        let didUpdateLocationNotification = expectation(description: "User update called")
        
        let user = User(userId: userId, publicSigningKey: Data(), publicName: nil)
        stub(userManager) { stub in
            when(stub.user(user.userId)).thenReturn(user)
        }
        stub(locationStorageManager) { stub in
            when(stub.locationSharingState(userId: user.userId, groupId: groupId)).thenReturn(LocationSharingState(userId: user.userId, groupId: groupId, enabled: true, lastUpdated: Date()))
        }
        stub(groupStorageManager) { stub in
            when(stub.isMember(userId: user.userId, groupId: groupId)).thenReturn(true)
        }
        
        notifier.register(UserLocationUpdateNotificationHandler.self, observer: self)
        didUpdateLocationCallback = { userId in
            defer { didUpdateLocationNotification.fulfill() }
            XCTAssertEqual(userId, user.userId, "Invalid callback")
        }
        
        let location = Location(latitude: 42.0, longitude: 1337.0, altitude: 4711.0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: Date())
        let locationUpdate = LocationUpdateV2(location: location, groupId: groupId)
        let payloadMetaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: user.userId, timestamp: Date(), collapseId: nil, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, conversationInvitation: nil)
        
        locationSharingManager.handleLocationUpdate(payload: locationUpdate, metaInfo: payloadMetaInfo) { result in
            defer { handlerCalled.fulfill() }
            
            guard let lastLocation = self.locationSharingManager.lastLocation(userId: user.userId, groupId: groupId) else {
                XCTFail("No last location existing")
                return
            }
            
            XCTAssertEqual(lastLocation.coordinate.latitude, locationUpdate.location.latitude, "Incorrect location")
            XCTAssertEqual(lastLocation.coordinate.longitude, locationUpdate.location.longitude, "Incorrect location")
            XCTAssertEqual(lastLocation.altitude, locationUpdate.location.altitude, "Incorrect location")
            XCTAssertEqual(lastLocation.horizontalAccuracy, locationUpdate.location.horizontalAccuracy, "Incorrect location")
            XCTAssertEqual(lastLocation.verticalAccuracy, locationUpdate.location.verticalAccuracy, "Incorrect location")
            XCTAssertGreaterThan(lastLocation.timestamp, Date().addingTimeInterval(-5.0), "Incorrect location")
            XCTAssertLessThan(lastLocation.timestamp, Date(), "Incorrect location")
        }
        
        wait(for: [handlerCalled, didUpdateLocationNotification])
    }
    
    func testHandleOldLocationUpdate() {
        let userId = UserId()
        let groupId = GroupId()
        let key = LocationSharingManager.UserGroupIds(userId: userId, groupId: groupId)
        
        let oldLocation = Location(coordinate: CLLocationCoordinate2D(latitude: 52.0, longitude: 13.0), altitude: 13.0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: Date())
        locationSharingManager.lastLocations = [key: oldLocation]
        
        let handlerCalled = expectation(description: "Completion")
        let didUpdateLocationNotification = expectation(description: "User update called")
        didUpdateLocationNotification.isInverted = true
        
        let user = User(userId: userId, publicSigningKey: Data(), publicName: nil)
        stub(userManager) { stub in
            when(stub.user(user.userId)).thenReturn(user)
        }
        stub(locationStorageManager) { stub in
            when(stub.locationRequired(userId: signedInUser.userId)).thenReturn(true)
            when(stub.locationSharingState(userId: user.userId, groupId: groupId)).thenReturn(LocationSharingState(userId: user.userId, groupId: groupId, enabled: true, lastUpdated: Date()))
        }
        stub(groupStorageManager) { stub in
            when(stub.isMember(userId: user.userId, groupId: groupId)).thenReturn(true)
        }
        
        notifier.register(UserLocationUpdateNotificationHandler.self, observer: self)
        didUpdateLocationCallback = { userId in
            defer { didUpdateLocationNotification.fulfill() }
            XCTAssertEqual(userId, user.userId, "Invalid callback")
        }
        
        let location = Location(latitude: 42.0, longitude: 1337.0, altitude: 4711.0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: Date().addingTimeInterval(-10.0))
        let locationUpdate = LocationUpdateV2(location: location, groupId: groupId)
        let payloadMetaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: user.userId, timestamp: Date(), collapseId: nil, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, conversationInvitation: nil)
        
        locationSharingManager.handleLocationUpdate(payload: locationUpdate, metaInfo: payloadMetaInfo) { result in
            defer { handlerCalled.fulfill() }
            
            guard let lastLocation = self.locationSharingManager.lastLocation(userId: user.userId, groupId: groupId) else {
                XCTFail("No last location existing")
                return
            }
            
            XCTAssertEqual(lastLocation.coordinate.latitude, oldLocation.latitude, "Incorrect location")
            XCTAssertEqual(lastLocation.coordinate.longitude, oldLocation.longitude, "Incorrect location")
            XCTAssertGreaterThan(lastLocation.timestamp, Date().addingTimeInterval(-1.0), "Incorrect location")
        }
        
        wait(for: [handlerCalled, didUpdateLocationNotification])
    }
    
    func testStoringLocationSharingState() throws {
        let userId = UserId()
        let groupId = GroupId()
        let enabled = true
        let lastUpdated = Date()
        stub(locationStorageManager) { when($0.storeLocationSharingState(userId: userId, groupId: groupId, enabled: enabled, lastUpdated: lastUpdated)).thenDoNothing() }
        try locationSharingManager.storeLocationSharingState(userId: userId, groupId: groupId, enabled: enabled, lastUpdated: lastUpdated)
        verify(locationStorageManager).storeLocationSharingState(userId: userId, groupId: groupId, enabled: enabled, lastUpdated: lastUpdated)
    }
    
    func testReceivingLocationUpdateWhileLocationSharingStateIsDisabled() throws {
        let userId = UserId()
        let groupId = GroupId()
        let handlerCalled = expectation(description: "Completion")
        let didUpdateLocationNotification = expectation(description: "User update called")
        
        let user = User(userId: userId, publicSigningKey: Data(), publicName: nil)
        stub(userManager) { stub in
            when(stub.user(user.userId)).thenReturn(user)
        }
        stub(locationStorageManager) { stub in
            when(stub.storeLocationSharingState(userId: userId, groupId: groupId, enabled: any(), lastUpdated: any())).thenDoNothing()
            when(stub.locationSharingState(userId: user.userId, groupId: groupId)).thenReturn(LocationSharingState(userId: user.userId, groupId: groupId, enabled: false, lastUpdated: Date()))
        }
        stub(groupStorageManager) { stub in
            when(stub.isMember(userId: user.userId, groupId: groupId)).thenReturn(true)
        }
        
        notifier.register(UserLocationUpdateNotificationHandler.self, observer: self)
        didUpdateLocationCallback = { userId in
            defer { didUpdateLocationNotification.fulfill() }
            XCTAssertEqual(userId, user.userId, "Invalid callback")
        }
        
        let locationDate = Date()
        let location = Location(latitude: 42.0, longitude: 1337.0, altitude: 4711.0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: locationDate)
        let locationUpdate = LocationUpdateV2(location: location, groupId: groupId)
        let payloadMetaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: user.userId, timestamp: Date(), collapseId: nil, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, conversationInvitation: nil)
        
        locationSharingManager.handleLocationUpdate(payload: locationUpdate, metaInfo: payloadMetaInfo) { result in
            defer { handlerCalled.fulfill() }
            verify(self.locationStorageManager).storeLocationSharingState(userId: user.userId, groupId: groupId, enabled: true, lastUpdated: locationDate)
        }
        
        wait(for: [handlerCalled, didUpdateLocationNotification])
    }
    
    func testReceivingOlderLocationUpdateAfterLocationSharingStateWasDisabled() throws {
        let userId = UserId()
        let groupId = GroupId()
        let handlerCalled = expectation(description: "Completion")
        let didUpdateLocationNotification = expectation(description: "User update called")
        
        let locationDate = Date()
        let locationSharingUpdateDate = locationDate.addingTimeInterval(1)
        
        let user = User(userId: userId, publicSigningKey: Data(), publicName: nil)
        stub(userManager) { stub in
            when(stub.user(user.userId)).thenReturn(user)
        }
        stub(locationStorageManager) { stub in
            when(stub.storeLocationSharingState(userId: userId, groupId: groupId, enabled: any(), lastUpdated: any())).thenDoNothing()
            when(stub.locationSharingState(userId: user.userId, groupId: groupId)).thenReturn(LocationSharingState(userId: user.userId, groupId: groupId, enabled: false, lastUpdated: locationSharingUpdateDate))
        }
        stub(groupStorageManager) { stub in
            when(stub.isMember(userId: user.userId, groupId: groupId)).thenReturn(true)
        }
        
        notifier.register(UserLocationUpdateNotificationHandler.self, observer: self)
        didUpdateLocationCallback = { userId in
            defer { didUpdateLocationNotification.fulfill() }
            XCTAssertEqual(userId, user.userId, "Invalid callback")
        }
        
        
        let location = Location(latitude: 42.0, longitude: 1337.0, altitude: 4711.0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: locationDate)
        let locationUpdate = LocationUpdateV2(location: location, groupId: groupId)
        let payloadMetaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: user.userId, timestamp: Date(), collapseId: nil, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, conversationInvitation: nil)
        
        locationSharingManager.handleLocationUpdate(payload: locationUpdate, metaInfo: payloadMetaInfo) { result in
            defer { handlerCalled.fulfill() }
            verify(self.locationStorageManager, never()).storeLocationSharingState(userId: user.userId, groupId: groupId, enabled: true, lastUpdated: locationDate)
        }
        
        wait(for: [handlerCalled, didUpdateLocationNotification])
    }
    
    func testCheckingForOutdatedLocationSharingStateWithOldLocation() throws {
        let userId = UserId()
        let groupId = GroupId()
        let key = LocationSharingManager.UserGroupIds(userId: userId, groupId: groupId)
        let oldLocation = Location(coordinate: CLLocationCoordinate2D(latitude: 52.0, longitude: 13.0), altitude: 13.0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: Date().addingTimeInterval(-10.0))
        locationSharingManager.lastLocations = [key: oldLocation]
        
        stub(locationStorageManager) { stub in
            when(stub.locationSharingStates(withEnabledState: true)).thenReturn([LocationSharingState(userId: userId, groupId: groupId, enabled: true, lastUpdated: oldLocation.timestamp)])
            when(stub.locationSharingState(userId: userId, groupId: groupId)).thenReturn(LocationSharingState(userId: userId, groupId: groupId, enabled: false, lastUpdated: oldLocation.timestamp))
            when(stub.storeLocationSharingState(userId: userId, groupId: groupId, enabled: false, lastUpdated: oldLocation.timestamp)).thenDoNothing()
        }
        
        locationSharingManager.checkOutdatedLocationSharingStates()
        verify(locationStorageManager).storeLocationSharingState(userId: userId, groupId: groupId, enabled: false, lastUpdated: oldLocation.timestamp)
    }
    
    func testCheckingForOutdatedLocationSharingStateWithoutOldLocation() throws {
        let userId = UserId()
        let groupId = GroupId()
        let date = Date() - 10.0
        
        stub(locationStorageManager) { stub in
            when(stub.locationSharingStates(withEnabledState: true)).thenReturn([LocationSharingState(userId: userId, groupId: groupId, enabled: true, lastUpdated: date)])
            when(stub.locationSharingState(userId: userId, groupId: groupId)).thenReturn(LocationSharingState(userId: userId, groupId: groupId, enabled: false, lastUpdated: date))
            when(stub.storeLocationSharingState(userId: userId, groupId: groupId, enabled: false, lastUpdated: date)).thenDoNothing()
        }
        
        locationSharingManager.checkOutdatedLocationSharingStates()
        verify(locationStorageManager).storeLocationSharingState(userId: userId, groupId: groupId, enabled: false, lastUpdated: date)
    }
    
    func testCheckingForOutdatedLocationSharingStateIgnoresSignedInUser() throws {
        let userId = signedInUser.userId
        let groupId = GroupId()
        let date = Date() - 10.0
        let oldLocation = Location(coordinate: CLLocationCoordinate2D(latitude: 52.0, longitude: 13.0), altitude: 13.0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: date)
        
        let key = LocationSharingManager.UserGroupIds(userId: userId, groupId: groupId)
        locationSharingManager.lastLocations = [key: oldLocation]
        
        stub(locationStorageManager) { stub in
            when(stub.locationSharingStates(withEnabledState: true)).thenReturn([LocationSharingState(userId: userId, groupId: groupId, enabled: true, lastUpdated: date)])
            when(stub.locationSharingState(userId: userId, groupId: groupId)).thenReturn(LocationSharingState(userId: userId, groupId: groupId, enabled: true, lastUpdated: date))
            when(stub.storeLocationSharingState(userId: userId, groupId: groupId, enabled: false, lastUpdated: date)).thenDoNothing()
        }
        
        locationSharingManager.checkOutdatedLocationSharingStates()
        verify(locationStorageManager, never()).storeLocationSharingState(userId: userId, groupId: groupId, enabled: false, lastUpdated: date)
    }
}

extension LocationSharingManagerTests: UserLocationUpdateNotificationHandler {
    func didUpdateLocation(userId: UserId) {
        didUpdateLocationCallback?(userId)
    }
}
