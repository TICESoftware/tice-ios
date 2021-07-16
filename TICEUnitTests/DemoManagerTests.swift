//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import XCTest
import Shouter
import TICEAPIModels
import CoreLocation
import Cuckoo

@testable import TICE

class DemoManagerTests: XCTestCase {

    var storage: MockDemoStorageManagerType!
    var tracker: MockTracker!
    
    override func setUp() {
        super.setUp()
        
        storage = MockDemoStorageManagerType()
        tracker = MockTracker()
    }
    
    func testInitialState() {
        stub(storage) { stub in
            when(stub.load()).thenReturn(nil)
        }
        let demoManager = DemoManager(storage: storage, notifier: Shouter(), tracker: tracker)
        XCTAssertFalse(demoManager.isDemoEnabled)
        XCTAssertFalse(demoManager.showMeetupButton.wrappedValue)
    }
    
    func testStateRestoration() {
        let storage = MockDemoStorageManagerType()
        stub(storage) { stub in
            let userOne = DemoUser(userId: UserId(), name: "NameOne", role: "RoleOne", location: nil)
            let userTwo = DemoUser(userId: UserId(), name: "NameTwo", role: "RoleTwo", location: nil)
            when(stub.load()).then {
                let demoTeam = DemoTeam(groupId: GroupId(), name: "name", userOne: userOne, userTwo: userTwo, userSharingLocation: false, demoUsersSharingLocation: false)
                return .init(step: .teamDeleted, team: demoTeam)}
        }
        
        let demoManager = DemoManager(storage: storage, notifier: Shouter(), tracker: tracker)
        XCTAssertFalse(demoManager.isDemoEnabled)
    }

    func testStateAdvancing() {
        let storage = MockDemoStorageManagerType()
        stub(storage) { stub in
            when(stub.load()).thenReturn(nil)
            when(stub.store(state: any(DemoManagerState.self))).thenDoNothing()
        }
        
        let demoManager = DemoManager(storage: storage, notifier: Shouter(), tracker: tracker)
        demoManager.didRegister()
        
        let argumentCaptor = ArgumentCaptor<DemoManagerState>()
        verify(storage).store(state: argumentCaptor.capture())
        XCTAssertEqual(argumentCaptor.value?.step, DemoManagerStep.notOpened)
    }
    
    func testHappyPath() {
        let storage = MockDemoStorageManagerType()
        stub(storage) { stub in
            when(stub.load()).thenReturn(nil)
            when(stub.store(state: any(DemoManagerState.self))).thenDoNothing()
        }
        
        let demoManager = DemoManager(storage: storage, notifier: Shouter(), tracker: tracker)
        demoManager.didRegister()
        demoManager.didOpenTeam()
        demoManager.didOpenChat()
        demoManager.didCloseChat()
        demoManager.didStartLocationSharing()
        demoManager.didCreateMeetingPoint(location: CLLocationCoordinate2D())
        demoManager.didSelectUser(user: demoManager.demoTeam.wrappedValue.members.first!)
        demoManager.didEndLocationSharing()
        
        let argumentCaptor = ArgumentCaptor<DemoManagerState>()
        verify(storage, atLeastOnce()).store(state: argumentCaptor.capture())
        XCTAssertEqual(argumentCaptor.value?.step, DemoManagerStep.locationSharingEnded)
    }
}
