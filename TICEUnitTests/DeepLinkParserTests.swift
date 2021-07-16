//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels
import Shouter
import XCTest
import PromiseKit
import Cuckoo

@testable import TICE

class DeepLinkParserTests: XCTestCase {

    var groupStorageManager: MockGroupStorageManagerType!
    var signedInUserController: MockSignedInUserManagerType!
    var cryptoManager: MockCryptoManagerType!
    var teamManager: MockTeamManagerType!
    var meetupManager: MockMeetupManagerType!
    var baseURL: URL = URL(string: "https://tice.app")!

    var deepLinkParser: DeepLinkParser!
    
    override func setUp() {
        groupStorageManager = MockGroupStorageManagerType()
        signedInUserController = MockSignedInUserManagerType()
        cryptoManager = MockCryptoManagerType()
        teamManager = MockTeamManagerType()
        meetupManager = MockMeetupManagerType()

        deepLinkParser = DeepLinkParser(teamManager: teamManager, meetupManager: meetupManager, groupStorageManager: groupStorageManager, baseURL: baseURL)
    }
    
    func testProcessTeam() throws {
        let completion = expectation(description: "completion")

        let teamId = GroupId()
        let team = Team(groupId: teamId, groupKey: "teamKey".data, owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "teamTag", url: URL(string: "https://tice.app/group/\(teamId)")!, name: "groupName", meetupId: nil)
        let shareURL = URL(string: "\(team.url)#\(team.groupKey.base64URLEncodedString())")!

        stub(teamManager) { stub in
            when(stub.getOrFetchTeam(groupId: teamId, groupKey: team.groupKey)).thenReturn(Promise.value(team))
        }

        firstly {
            deepLinkParser.team(url: shareURL)
        }.done { fetchedTeam in
            XCTAssertEqual(fetchedTeam.groupId, team.groupId, "Invalid group id")
        }.catch {
            XCTFail(String(describing: $0))
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testSettingsFromDeepLink() throws {

        let completion = expectation(description: "completion")
        firstly {
            deepLinkParser.state(url: baseURL.appendingPathComponent("settings"))
        }.done { state in
            XCTAssertEqual(state, .main(.settings))
        }.catch {
            XCTFail(String(describing: $0))
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testJoinFromDeepLink() throws {
        let completion = expectation(description: "completion")

        let teamId = GroupId()
        let team = Team(groupId: teamId, groupKey: "teamKey".data, owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "teamTag", url: URL(string: "https://tice.app/group/\(teamId)")!, name: "groupName", meetupId: nil)
        let shareURL = URL(string: "\(team.url)#\(team.groupKey.base64URLEncodedString())")!

        stub(teamManager) { stub in
            when(stub.teamWith(groupId: teamId)).thenReturn(nil)
            when(stub.getOrFetchTeam(groupId: teamId, groupKey: team.groupKey)).thenReturn(Promise.value(team))
        }

        firstly {
            deepLinkParser.state(url: shareURL)
        }.done { state in
            XCTAssertEqual(state, .main(.join(team: team)))
        }.catch {
            XCTFail(String(describing: $0))
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }
}
