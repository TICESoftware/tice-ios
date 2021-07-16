//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import XCTest
import GRDB
import PromiseKit

@testable import TICE

class MigrationTo2_0_0_128Tests: XCTestCase {
    
    func testMigrateDemoState() throws {
        
        let anna = DemoUserPre128(userId: UserId(), name: "Anna", role: "Member", location: Coordinate(latitude: 1, longitude: 2))
        let bert = DemoUserPre128(userId: UserId(), name: "Bert", role: "Member", location: Coordinate(latitude: 3, longitude: 4))
        let oldDemoState = DemoManagerStatePre128(step: .meetingPointCreated, team: DemoTeamPre128(groupId: GroupId(), name: "Test Group", userOne: anna, userTwo: bert, meetup: DemoMeetupPre128(groupId: GroupId(), location: Coordinate(latitude: 52, longitude: 13), timestamp: Date(), meetingPoint: Coordinate(latitude: 13, longitude: 37))))
        
        let appBundleId = Bundle.main.appBundleId
        let appGroupName = "group." + appBundleId
        let userDefaults = UserDefaults(suiteName: appGroupName)!
        let encoder = JSONEncoder.encoderWithFractionalSeconds
        let oldData = try encoder.encode(oldDemoState)
        userDefaults.set(oldData, forKey: "state")
        
        let completion = expectation(description: "Completion")
        
        firstly { () -> Promise<Void> in
            let migration = MigrationTo2_0_0_128(userDefaults: userDefaults)
            return migration.migrate()
        }.done {
            let decoder = JSONDecoder.decoderWithFractionalSeconds
            let data = userDefaults.data(forKey: "state")!
            let state = try decoder.decode(DemoManagerState.self, from: data)
            XCTAssertEqual(state.team.groupId, oldDemoState.team.groupId)
            XCTAssertEqual(state.team.meetingPoint, oldDemoState.team.meetup?.meetingPoint)
            XCTAssertEqual(state.team.location, oldDemoState.team.meetup?.location)
            XCTAssertTrue(state.team.userSharingLocation)
            XCTAssertEqual(state.step, .meetingPointCreated)
        }.catch {
            XCTFail(String(describing: $0))
        }.finally {
            completion.fulfill()
        }
        
        wait(for: [completion])
    }
    
    func testMigrateFinishedDemoState() throws {
        
        let anna = DemoUserPre128(userId: UserId(), name: "Anna", role: "Member", location: Coordinate(latitude: 1, longitude: 2))
        let bert = DemoUserPre128(userId: UserId(), name: "Bert", role: "Member", location: Coordinate(latitude: 3, longitude: 4))
        let oldDemoState = DemoManagerStatePre128(step: .teamDeleted, team: DemoTeamPre128(groupId: GroupId(), name: "Test Group", userOne: anna, userTwo: bert, meetup: nil))
        
        let appBundleId = Bundle.main.appBundleId
        let appGroupName = "group." + appBundleId
        let userDefaults = UserDefaults(suiteName: appGroupName)!
        let encoder = JSONEncoder.encoderWithFractionalSeconds
        let oldData = try encoder.encode(oldDemoState)
        userDefaults.set(oldData, forKey: "state")
        
        let completion = expectation(description: "Completion")
        
        firstly { () -> Promise<Void> in
            let migration = MigrationTo2_0_0_128(userDefaults: userDefaults)
            return migration.migrate()
        }.done {
            let decoder = JSONDecoder.decoderWithFractionalSeconds
            let data = userDefaults.data(forKey: "state")!
            let state = try decoder.decode(DemoManagerState.self, from: data)
            XCTAssertEqual(state.step, .teamDeleted)
        }.catch {
            XCTFail(String(describing: $0))
        }.finally {
            completion.fulfill()
        }
        
        wait(for: [completion])
    }
}
