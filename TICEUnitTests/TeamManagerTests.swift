//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import XCTest
import TICEAPIModels
import PromiseKit
import Shouter
import Cuckoo

@testable import TICE

class TeamManagerTests: XCTestCase {

    var groupManager: MockGroupManagerType!
    var meetupManager: MockMeetupManagerType!
    var groupStorageManager: MockGroupStorageManagerType!
    var signedInUser: SignedInUser!
    var cryptoManager: MockCryptoManagerType!
    var authManager: MockAuthManagerType!
    var userManager: MockUserManagerType!
    var locationManager: MockLocationManagerType!
    var locationStorageManager: MockLocationStorageManagerType!
    var backend: MockTICEAPI!
    var mailbox: MockMailboxType!
    var encoder: JSONEncoder!
    var decoder: JSONDecoder!

    var team: Team!
    var membership: Membership!

    var teamManager: TeamManager!

    override func setUp() {
        groupManager = MockGroupManagerType()
        meetupManager = MockMeetupManagerType()
        groupStorageManager = MockGroupStorageManagerType()
        signedInUser = SignedInUser(userId: UserId(), privateSigningKey: Data(), publicSigningKey: Data(), publicName: nil)
        cryptoManager = MockCryptoManagerType()
        authManager = MockAuthManagerType()
        userManager = MockUserManagerType()
        locationManager = MockLocationManagerType()
        locationStorageManager = MockLocationStorageManagerType()
        backend = MockTICEAPI()
        mailbox = MockMailboxType()
        encoder = JSONEncoder()
        decoder = JSONDecoder()

        let groupId = GroupId()
        let groupKey = "groupKey".data
        let groupURL = URL(string: "https://develop.tice.app/group/\(groupId)")!
        team = Team(groupId: groupId, groupKey: groupKey, owner: signedInUser.userId, joinMode: .open, permissionMode: .everyone, tag: "groupTag", url: groupURL, name: "groupName", meetupId: nil)

        let selfSignedCertificate = "selfSignedCertificate"
        let serverSignedCertificate = "serverSignedCertificate"
        membership = Membership(userId: signedInUser.userId, publicSigningKey: signedInUser.publicSigningKey, groupId: team.groupId, admin: true, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedMembershipCertificate: serverSignedCertificate, adminSignedMembershipCertificate: selfSignedCertificate)

        teamManager = TeamManager(groupManager: groupManager, meetupManager: meetupManager, groupStorageManager: groupStorageManager, signedInUser: signedInUser, cryptoManager: cryptoManager, authManager: authManager, userManager: userManager, locationManager: locationManager, locationStorageManager: locationStorageManager, backend: backend, mailbox: mailbox, encoder: encoder, decoder: decoder)
    }
    
    func testSetup() {
        stub(meetupManager) { stub in
            when(stub.teamReloader.set(any())).thenDoNothing()
        }
        
        stub(locationManager) { stub in
            when(stub.delegate.set(any())).thenDoNothing()
        }
        
        teamManager.setup()
        
        verify(meetupManager).teamReloader.set(any())
    }

    func testGetTeam() {
        stub(groupStorageManager) { stub in
            when(stub.loadTeam(team.groupId)).thenReturn(self.team)
        }

        XCTAssertEqual(teamManager.teamWith(groupId: team.groupId)?.groupId, team.groupId, "Invalid team")

        verify(groupStorageManager).loadTeam(team.groupId)
    }

    func testGetTeams() {
        stub(groupStorageManager) { stub in
            when(stub.loadTeams()).thenReturn([self.team])
        }

        let teams = teamManager.teams
        XCTAssertEqual(teams.count, 1, "Invalid teams")
        XCTAssertEqual(teams.first?.groupId, team.groupId, "Invalid teams")

        verify(groupStorageManager).loadTeams()
    }

    func testCreateTeam() throws {
        let groupSettings = GroupSettings(owner: signedInUser.userId, name: team.name)
        let groupSettingsData = try encoder.encode(groupSettings)
        let encryptedGroupSettings = "encryptedGroupSettings".data

        let internalTeamSettings = InternalTeamSettings(meetingPoint: nil)
        let internalTeamSettingsData = try encoder.encode(internalTeamSettings)
        let encryptedInternalSettings = "encryptedInternalSettings".data

        let selfSignedAdminCertificate = "selfSignedAdminCertificate"
        
        stub(authManager) { stub in
            when(stub.createUserSignedMembershipCertificate(userId: signedInUser.userId, groupId: any(GroupId.self), admin: true, issuerUserId: signedInUser.userId, signingKey: signedInUser.privateSigningKey)).thenReturn(selfSignedAdminCertificate)
        }

        stub(cryptoManager) { stub in
            when(stub.generateGroupKey()).thenReturn(team.groupKey)
            when(stub.encrypt(groupSettingsData, secretKey: team.groupKey)).thenReturn(encryptedGroupSettings)
            when(stub.encrypt(internalTeamSettingsData, secretKey: team.groupKey)).thenReturn(encryptedInternalSettings)
        }

        let groupTagAfterCreating = "groupTag1"
        let groupTagAfterAddingMember = "groupTag2"

        stub(groupStorageManager) { stub in
            when(stub.loadMemberships(groupId: any())).thenReturn([])
            when(stub.storeTeam(any(Team.self))).thenDoNothing()
            when(stub.store(any(Membership.self))).thenDoNothing()
            when(stub.updateTeamTag(groupId: any(GroupId.self), tag: groupTagAfterAddingMember)).thenDoNothing()
        }

        let serverSignedCertificate = "serverSignedAdminCertificate"
        let createGroupResponse = CreateGroupResponse(url: team.url, serverSignedAdminCertificate: serverSignedCertificate, groupTag: groupTagAfterCreating)

        stub(backend) { stub in
            when(stub.createGroup(userId: signedInUser.userId, type: GroupType.team, joinMode: JoinMode.open, permissionMode: PermissionMode.everyone, groupId: any(GroupId.self), parentGroup: nil as ParentGroup?, selfSignedAdminCertificate: selfSignedAdminCertificate, encryptedSettings: encryptedGroupSettings, encryptedInternalSettings: encryptedInternalSettings)).thenReturn(Promise.value(createGroupResponse))
        }

        stub(groupManager) { stub in
            when(stub.addUserMember(into: any(), admin: true, serverSignedMembershipCertificate: serverSignedCertificate)).then { team, _, _ -> Promise<(Membership, GroupTag)> in
                let membership = Membership(userId: self.signedInUser.userId, publicSigningKey: self.signedInUser.publicSigningKey, groupId: team.groupId, admin: true, selfSignedMembershipCertificate: selfSignedAdminCertificate, serverSignedMembershipCertificate: serverSignedCertificate, adminSignedMembershipCertificate: selfSignedAdminCertificate)
                return Promise.value((membership, groupTagAfterAddingMember))
            }
        }
        
        stub(locationStorageManager) { stub in
            when(stub.storeLocationSharingState(userId: any(), groupId: any(), enabled: any(), lastUpdated: any())).thenDoNothing()
        }

        let completion = expectation(description: "Completion")

        firstly {
            teamManager.createTeam(joinMode: self.team.joinMode, permissionMode: self.team.permissionMode, name: self.team.name, shareLocation: false, meetingPoint: nil)
        }.done { team in
            let teamArgumentCaptor = ArgumentCaptor<Team>()
            verify(self.groupStorageManager).storeTeam(teamArgumentCaptor.capture())
            guard let storedTeam = teamArgumentCaptor.value else {
                XCTFail("Invalid team stored")
                return
            }

            XCTAssertEqual(storedTeam.joinMode, self.team.joinMode, "Invalid group")
            XCTAssertEqual(storedTeam.permissionMode, self.team.permissionMode, "Invalid group")
            XCTAssertEqual(storedTeam.groupKey, self.team.groupKey, "Invalid group")
            XCTAssertEqual(storedTeam.owner, self.signedInUser.userId, "Invalid group")
            XCTAssertEqual(storedTeam.url, self.team.url, "Invalid group")
            XCTAssertEqual(storedTeam.tag, groupTagAfterCreating, "Invalid group")
            XCTAssertEqual(storedTeam.name, self.team.name, "Invalid group")
            XCTAssertNil(storedTeam.meetupId, "Invalid group")
            XCTAssertNil(storedTeam.meetingPoint, "Invalid group")

            let membershipCheck = Membership(userId: self.signedInUser.userId, publicSigningKey: self.signedInUser.publicSigningKey, groupId: team.groupId, admin: true, selfSignedMembershipCertificate: selfSignedAdminCertificate, serverSignedMembershipCertificate: serverSignedCertificate, adminSignedMembershipCertificate: selfSignedAdminCertificate)
            verify(self.groupStorageManager).store(membershipCheck)

            verify(self.groupStorageManager).updateTeamTag(groupId: team.groupId, tag: groupTagAfterAddingMember)
        }.catch { error in
            XCTFail(String(describing: error))
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testReloadTeamModified() throws {
        let completion = expectation(description: "Completion")

        stub(groupStorageManager) { stub in
            when(stub.isMember(userId: signedInUser.userId, groupId: team.groupId)).thenReturn(true)
            when(stub.loadMembership(userId: signedInUser.userId, groupId: team.groupId)).thenReturn(membership)
            when(stub.storeTeam(any(Team.self))).thenDoNothing()
            when(stub.store(any([Membership].self), for: team.groupId)).thenDoNothing()
        }

        let encryptedGroupSettings = "encryptedGroupSettings".data
		let encryptedInternalSettings = "encryptedInternalSettings".data
        let encryptedMembership = "encryptedMembership".data
        let updatedTag = "updatedTag"

        let groupInternalsResponse = GroupInternalsResponse(groupId: team.groupId, parentGroupId: nil, type: .team, joinMode: team.joinMode, permissionMode: team.permissionMode, url: team.url, encryptedSettings: encryptedGroupSettings, encryptedInternalSettings: encryptedInternalSettings, encryptedMemberships: [encryptedMembership], parentEncryptedGroupKey: nil, children: [], groupTag: updatedTag)

        stub(backend) { stub in
            when(stub.getGroupInternals(groupId: team.groupId, serverSignedMembershipCertificate: membership.serverSignedMembershipCertificate, groupTag: team.tag)).thenReturn(Promise.value(groupInternalsResponse))
        }

        let settings = GroupSettings(owner: team.owner, name: team.name)
        let encodedSettings = try encoder.encode(settings)
        let encodedInternalSettings = try encoder.encode(InternalTeamSettings(meetingPoint: nil))
        let encodedMembership = try encoder.encode(membership)
        stub(cryptoManager) { stub in
            when(stub.decrypt(encryptedData: encryptedGroupSettings, secretKey: team.groupKey)).thenReturn(encodedSettings)
            when(stub.decrypt(encryptedData: encryptedMembership, secretKey: team.groupKey)).thenReturn(encodedMembership)
            when(stub.decrypt(encryptedData: encryptedInternalSettings, secretKey: team.groupKey)).thenReturn(encodedInternalSettings)
        }

        stub(userManager) { stub in
            when(stub.getUser(signedInUser.userId)).thenReturn(Promise.value(signedInUser))
        }

        firstly {
            teamManager.reload(team: team, reloadMeetup: false)
        }.done { team in

            let teamArgumentCaptor = ArgumentCaptor<Team>()
            verify(self.groupStorageManager).storeTeam(teamArgumentCaptor.capture())
            guard let storedTeam = teamArgumentCaptor.value else {
                XCTFail("Invalid team stored")
                return
            }

            XCTAssertEqual(storedTeam.joinMode, self.team.joinMode, "Invalid group")
            XCTAssertEqual(storedTeam.permissionMode, self.team.permissionMode, "Invalid group")
            XCTAssertEqual(storedTeam.groupKey, self.team.groupKey, "Invalid group")
            XCTAssertEqual(storedTeam.owner, self.signedInUser.userId, "Invalid group")
            XCTAssertEqual(storedTeam.url, self.team.url, "Invalid group")
            XCTAssertEqual(storedTeam.tag, updatedTag, "Invalid group")
            XCTAssertEqual(storedTeam.name, self.team.name, "Invalid group")
            XCTAssertNil(storedTeam.meetupId, "Invalid group")
            XCTAssertNil(storedTeam.meetingPoint, "Invalid group")

            XCTAssertEqual(team.groupId, self.team.groupId, "Invalid group")
            XCTAssertEqual(team.tag, updatedTag, "Invalid group")

            verify(self.groupStorageManager).store([self.membership], for: team.groupId)
        }.catch { error in
            XCTFail(String(describing: error))
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testReloadTeamNotModified() throws {
        let completion = expectation(description: "Completion")

        stub(groupStorageManager) { stub in
            when(stub.isMember(userId: signedInUser.userId, groupId: team.groupId)).thenReturn(true)
            when(stub.loadMembership(userId: signedInUser.userId, groupId: team.groupId)).thenReturn(membership)
        }

        stub(backend) { stub in
            when(stub.getGroupInternals(groupId: team.groupId, serverSignedMembershipCertificate: membership.serverSignedMembershipCertificate, groupTag: team.tag)).thenReturn(Promise.init(error: BackendError.notModified))
        }

        firstly {
            teamManager.reload(team: team, reloadMeetup: false)
        }.done { team in
            XCTAssertEqual(team.joinMode, self.team.joinMode, "Invalid group")
            XCTAssertEqual(team.permissionMode, self.team.permissionMode, "Invalid group")
            XCTAssertEqual(team.groupKey, self.team.groupKey, "Invalid group")
            XCTAssertEqual(team.owner, self.signedInUser.userId, "Invalid group")
            XCTAssertEqual(team.url, self.team.url, "Invalid group")
            XCTAssertEqual(team.tag, self.team.tag, "Invalid group")
            XCTAssertEqual(team.name, self.team.name, "Invalid group")
            XCTAssertNil(team.meetupId, "Invalid group")
            XCTAssertNil(team.meetingPoint, "Invalid group")
            XCTAssertEqual(team.groupId, self.team.groupId, "Invalid group")
        }.catch { error in
            XCTFail(String(describing: error))
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testReloadTeamNotMember() throws {
        let completion = expectation(description: "Completion")

        stub(groupStorageManager) { stub in
            when(stub.isMember(userId: signedInUser.userId, groupId: team.groupId)).thenReturn(false)
        }

        firstly {
            teamManager.reload(team: team)
        }.done { team in
            XCTFail("Reloading should not have succeeded")
        }.catch { error in
            guard case TeamManagerError.notMember = error else {
                XCTFail(String(describing: error))
                return
            }
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testReloadTeamNotFound() throws {
        let completion = expectation(description: "Completion")

        stub(groupStorageManager) { stub in
            when(stub.isMember(userId: signedInUser.userId, groupId: team.groupId)).thenReturn(true)
            when(stub.loadMembership(userId: signedInUser.userId, groupId: team.groupId)).thenReturn(membership)
            when(stub.removeTeam(team.groupId)).thenDoNothing()
        }

        stub(backend) { stub in
            when(stub.getGroupInternals(groupId: team.groupId, serverSignedMembershipCertificate: membership.serverSignedMembershipCertificate, groupTag: team.tag)).thenReturn(Promise.init(error: APIError(type: .notFound)))
        }

        firstly {
            teamManager.reload(team: team, reloadMeetup: false)
        }.done { team in
            XCTFail("Reloading should not have succeeded")
        }.catch { error in
            guard let apiError = error as? APIError, apiError.type == .notFound else {
                XCTFail(String(describing: error))
                return
            }
            verify(self.groupStorageManager).removeTeam(self.team.groupId)
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testReloadTeamUnauthorized() throws {
        let completion = expectation(description: "Completion")

        stub(groupStorageManager) { stub in
            when(stub.isMember(userId: signedInUser.userId, groupId: team.groupId)).thenReturn(true)
            when(stub.loadMembership(userId: signedInUser.userId, groupId: team.groupId)).thenReturn(membership)
            when(stub.removeTeam(team.groupId)).thenDoNothing()
        }

        stub(backend) { stub in
            when(stub.getGroupInternals(groupId: team.groupId, serverSignedMembershipCertificate: membership.serverSignedMembershipCertificate, groupTag: team.tag)).thenReturn(Promise.init(error: BackendError.unauthorized))
        }

        firstly {
            teamManager.reload(team: team)
        }.done { team in
            XCTFail("Reloading should not have succeeded")
        }.catch { error in
            guard case BackendError.unauthorized = error else {
                XCTFail(String(describing: error))
                return
            }
            verify(self.groupStorageManager).removeTeam(self.team.groupId)
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testReloadAllTeams() {
        let completion = expectation(description: "Completion")

        stub(groupStorageManager) { stub in
            when(stub.loadTeams()).thenReturn(Array(repeating: team, count: 2))
            when(stub.isMember(userId: signedInUser.userId, groupId: team.groupId)).thenReturn(false)
        }

        firstly {
            teamManager.reloadAllTeams()
        }.done {
            verify(self.groupStorageManager, times(2)).isMember(userId: self.signedInUser.userId, groupId: self.team.groupId)
        }.catch { error in
            XCTFail(String(describing: error))
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testGetOrFetchTeamNotStored() throws {
        let completion = expectation(description: "Completion")

        let encryptedSettings = "encryptedSettings".data
        let groupInformationResponse = GroupInformationResponse(groupId: team.groupId, parentGroupId: nil, type: .team, joinMode: team.joinMode, permissionMode: team.permissionMode, url: team.url, encryptedSettings: encryptedSettings, groupTag: team.tag)

        stub(groupStorageManager) { stub in
            when(stub.loadTeam(team.groupId)).thenReturn(nil)
        }

        stub(backend) { stub in
            when(stub.getGroupInformation(groupId: team.groupId, groupTag: nil as GroupTag?)).thenReturn(Promise.value(groupInformationResponse))
        }

        let groupSettings = GroupSettings(owner: team.owner, name: team.name)
        let groupSettingsData = try encoder.encode(groupSettings)

        stub(cryptoManager) { stub in
            when(stub.decrypt(encryptedData: encryptedSettings, secretKey: team.groupKey)).thenReturn(groupSettingsData)
        }

        firstly {
            teamManager.getOrFetchTeam(groupId: team.groupId, groupKey: team.groupKey)
        }.done { team in
            XCTAssertEqual(team.joinMode, self.team.joinMode, "Invalid group")
            XCTAssertEqual(team.permissionMode, self.team.permissionMode, "Invalid group")
            XCTAssertEqual(team.groupKey, self.team.groupKey, "Invalid group")
            XCTAssertEqual(team.owner, self.signedInUser.userId, "Invalid group")
            XCTAssertEqual(team.url, self.team.url, "Invalid group")
            XCTAssertEqual(team.tag, self.team.tag, "Invalid group")
            XCTAssertEqual(team.name, self.team.name, "Invalid group")
            XCTAssertNil(team.meetupId, "Invalid group")
            XCTAssertEqual(team.groupId, self.team.groupId, "Invalid group")
        }.catch { error in
            XCTFail(String(describing: error))
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testGetOrFetchTeamStored() throws {
        let completion = expectation(description: "Completion")

        stub(groupStorageManager) { stub in
            when(stub.loadTeam(team.groupId)).thenReturn(team)
        }

        firstly {
            teamManager.getOrFetchTeam(groupId: team.groupId, groupKey: team.groupKey)
        }.done { team in
            XCTAssertEqual(team.joinMode, self.team.joinMode, "Invalid group")
            XCTAssertEqual(team.permissionMode, self.team.permissionMode, "Invalid group")
            XCTAssertEqual(team.groupKey, self.team.groupKey, "Invalid group")
            XCTAssertEqual(team.owner, self.signedInUser.userId, "Invalid group")
            XCTAssertEqual(team.url, self.team.url, "Invalid group")
            XCTAssertEqual(team.tag, self.team.tag, "Invalid group")
            XCTAssertEqual(team.name, self.team.name, "Invalid group")
            XCTAssertNil(team.meetupId, "Invalid group")
            XCTAssertEqual(team.groupId, self.team.groupId, "Invalid group")
        }.catch { error in
            XCTFail(String(describing: error))
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testJoinTeamWithoutMeetup() throws {
        let completion = expectation(description: "Completion")

        let selfSignedCertificate = "selfSignedCertificate"
        let serverSignedCertificate = "serverSignedCertificate"
        let updatedTag = "updatedTag"
        let meetingPoint = Location(latitude: 52, longitude: 13)

        let newMembership = Membership(userId: self.signedInUser.userId, publicSigningKey: self.signedInUser.publicSigningKey, groupId: team.groupId, admin: true, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedMembershipCertificate: serverSignedCertificate, adminSignedMembershipCertificate: nil)

        stub(groupStorageManager) { stub in
            when(stub.isMember(userId: signedInUser.userId, groupId: team.groupId)).thenReturn(false)
            when(stub.storeTeam(any(Team.self))).thenDoNothing()
            when(stub.store(newMembership)).thenDoNothing()
            when(stub.store(any([Membership].self), for: team.groupId)).thenDoNothing()
            when(stub.updateTeamTag(groupId: team.groupId, tag: updatedTag)).thenDoNothing()
        }

        let encodedSettings = try encoder.encode(GroupSettings(owner: team.owner, name: team.name))
        let encodedInternalGroupSettings = try encoder.encode(InternalTeamSettings(meetingPoint: meetingPoint))
        let encodedMembership = try encoder.encode(membership)

        let encryptedGroupSettings = "encryptedGroupSettings".data
		let encryptedInternalSettings = "encryptedInternalSettings".data
        let encryptedMembership = "encryptedMembership".data

        stub(authManager) { stub in
            when(stub.createUserSignedMembershipCertificate(userId: signedInUser.userId, groupId: team.groupId, admin: false, issuerUserId: signedInUser.userId, signingKey: signedInUser.privateSigningKey)).thenReturn(selfSignedCertificate)
        }
        
        stub(cryptoManager) { stub in
            when(stub.decrypt(encryptedData: encryptedGroupSettings, secretKey: team.groupKey)).thenReturn(encodedSettings)
            when(stub.decrypt(encryptedData: encryptedInternalSettings, secretKey: team.groupKey)).thenReturn(encodedInternalGroupSettings)
            when(stub.decrypt(encryptedData: encryptedMembership, secretKey: team.groupKey)).thenReturn(encodedMembership)
        }

        let joinGroupResponse = JoinGroupResponse(serverSignedMembershipCertificate: serverSignedCertificate)

        let groupInternalsResponse = GroupInternalsResponse(groupId: team.groupId, parentGroupId: nil, type: .team, joinMode: team.joinMode, permissionMode: team.permissionMode, url: team.url, encryptedSettings: encryptedGroupSettings, encryptedInternalSettings: encryptedInternalSettings, encryptedMemberships: [encryptedMembership], parentEncryptedGroupKey: nil, children: [], groupTag: team.tag)
        stub(backend) { stub in
            when(stub.joinGroup(groupId: team.groupId, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedAdminCertificate: nil as Certificate?, adminSignedMembershipCertificate: nil as Certificate?, groupTag: team.tag)).thenReturn(Promise.value(joinGroupResponse))
            when(stub.getGroupInternals(groupId: team.groupId, serverSignedMembershipCertificate: serverSignedCertificate, groupTag: nil as GroupTag?)).thenReturn(Promise.value(groupInternalsResponse))
        }

        stub(groupManager) { stub in
            when(stub.addUserMember(into: any(), admin: false, serverSignedMembershipCertificate: serverSignedCertificate)).thenReturn(Promise.value((newMembership, updatedTag)))
        }

        stub(userManager) { stub in
            when(stub.getUser(signedInUser.userId)).thenReturn(Promise.value(signedInUser))
        }

        firstly {
            teamManager.join(team)
        }.done { team in
            XCTAssertEqual(team.joinMode, self.team.joinMode, "Invalid group")
            XCTAssertEqual(team.permissionMode, self.team.permissionMode, "Invalid group")
            XCTAssertEqual(team.groupKey, self.team.groupKey, "Invalid group")
            XCTAssertEqual(team.owner, self.signedInUser.userId, "Invalid group")
            XCTAssertEqual(team.url, self.team.url, "Invalid group")
            XCTAssertEqual(team.tag, updatedTag, "Invalid group")
            XCTAssertEqual(team.name, self.team.name, "Invalid group")
            XCTAssertNil(team.meetupId, "Invalid group")
            XCTAssertEqual(team.groupId, self.team.groupId, "Invalid group")
            XCTAssertEqual(team.meetingPoint, meetingPoint, "Invalid group")
        }.catch { error in
            XCTFail(String(describing: error))
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testJoinTeamWithMeetup() throws {
        let completion = expectation(description: "Completion")

        let selfSignedCertificate = "selfSignedCertificate"
        let serverSignedCertificate = "serverSignedCertificate"
        let updatedTag = "updatedTag"

        let newMembership = Membership(userId: self.signedInUser.userId, publicSigningKey: self.signedInUser.publicSigningKey, groupId: team.groupId, admin: true, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedMembershipCertificate: serverSignedCertificate, adminSignedMembershipCertificate: nil)

        stub(groupStorageManager) { stub in
            when(stub.isMember(userId: signedInUser.userId, groupId: team.groupId)).thenReturn(false)
            when(stub.storeTeam(any(Team.self))).thenDoNothing()
            when(stub.store(newMembership)).thenDoNothing()
            when(stub.store(any([Membership].self), for: team.groupId)).thenDoNothing()
            when(stub.updateTeamTag(groupId: team.groupId, tag: updatedTag)).thenDoNothing()
        }

        let settings = GroupSettings(owner: team.owner, name: team.name)
        let encodedSettings = try encoder.encode(settings)
        let encodedInternalSettings = try encoder.encode(InternalTeamSettings(meetingPoint: nil))
        let encodedMembership = try encoder.encode(membership)

        let encryptedGroupSettings = "encryptedGroupSettings".data
		let encryptedInternalSettings = "encryptedInternalSettings".data
        let encryptedMembership = "encryptedMembership".data
        
        stub(authManager) { stub in
            when(stub.createUserSignedMembershipCertificate(userId: signedInUser.userId, groupId: team.groupId, admin: false, issuerUserId: signedInUser.userId, signingKey: signedInUser.privateSigningKey)).thenReturn(selfSignedCertificate)
        }

        stub(cryptoManager) { stub in
            when(stub.decrypt(encryptedData: encryptedGroupSettings, secretKey: team.groupKey)).thenReturn(encodedSettings)
            when(stub.decrypt(encryptedData: encryptedInternalSettings, secretKey: team.groupKey)).thenReturn(encodedInternalSettings)
            when(stub.decrypt(encryptedData: encryptedMembership, secretKey: team.groupKey)).thenReturn(encodedMembership)
        }

        let joinGroupResponse = JoinGroupResponse(serverSignedMembershipCertificate: serverSignedCertificate)

        
        let meetup = Meetup(groupId: GroupId(), groupKey: SecretKey(), owner: team.owner, joinMode: .open, permissionMode: .everyone, tag: "groupTap", teamId: team.groupId, meetingPoint: nil, locationSharingEnabled: true)
        let meetupId = meetup.groupId
        
        let groupInternalsResponse = GroupInternalsResponse(groupId: team.groupId, parentGroupId: nil, type: .team, joinMode: team.joinMode, permissionMode: team.permissionMode, url: team.url, encryptedSettings: encryptedGroupSettings, encryptedInternalSettings: encryptedInternalSettings, encryptedMemberships: [encryptedMembership], parentEncryptedGroupKey: nil, children: [meetupId], groupTag: team.tag)
        stub(backend) { stub in
            when(stub.joinGroup(groupId: team.groupId, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedAdminCertificate: nil as Certificate?, adminSignedMembershipCertificate: nil as Certificate?, groupTag: team.tag)).thenReturn(Promise.value(joinGroupResponse))
            when(stub.getGroupInternals(groupId: team.groupId, serverSignedMembershipCertificate: serverSignedCertificate, groupTag: nil as GroupTag?)).thenReturn(Promise.value(groupInternalsResponse))
        }

        stub(meetupManager) { stub in
            when(stub.addOrReload(meetupId: meetupId, teamId: team.groupId)).thenReturn(.value(meetup))
        }

        stub(groupManager) { stub in
            when(stub.addUserMember(into: any(), admin: false, serverSignedMembershipCertificate: serverSignedCertificate)).thenReturn(Promise.value((newMembership, updatedTag)))
        }

        stub(userManager) { stub in
            when(stub.getUser(signedInUser.userId)).thenReturn(Promise.value(signedInUser))
        }

        firstly {
            teamManager.join(team)
        }.done { team in
            XCTAssertEqual(team.joinMode, self.team.joinMode, "Invalid group")
            XCTAssertEqual(team.permissionMode, self.team.permissionMode, "Invalid group")
            XCTAssertEqual(team.groupKey, self.team.groupKey, "Invalid group")
            XCTAssertEqual(team.owner, self.signedInUser.userId, "Invalid group")
            XCTAssertEqual(team.url, self.team.url, "Invalid group")
            XCTAssertEqual(team.tag, updatedTag, "Invalid group")
            XCTAssertEqual(team.name, self.team.name, "Invalid group")
            XCTAssertEqual(team.meetupId, meetupId, "Invalid group")
            XCTAssertEqual(team.groupId, self.team.groupId, "Invalid group")

            verify(self.meetupManager).addOrReload(meetupId: meetupId, teamId: team.groupId)
        }.catch { error in
            XCTFail(String(describing: error))
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testJoinOutdatedTeam() throws {
        let completion = expectation(description: "Completion")

        let selfSignedCertificate = "selfSignedCertificate"

        stub(groupStorageManager) { stub in
            when(stub.isMember(userId: signedInUser.userId, groupId: team.groupId)).thenReturn(false)
        }
        
        stub(authManager) { stub in
            when(stub.createUserSignedMembershipCertificate(userId: signedInUser.userId, groupId: team.groupId, admin: false, issuerUserId: signedInUser.userId, signingKey: signedInUser.privateSigningKey)).thenReturn(selfSignedCertificate)
        }

        stub(backend) { stub in
            when(stub.joinGroup(groupId: team.groupId, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedAdminCertificate: nil as Certificate?, adminSignedMembershipCertificate: nil as Certificate?, groupTag: team.tag)).thenReturn(Promise.init(error: APIError(type: .invalidGroupTag)))
        }

        firstly {
            teamManager.join(team)
        }.done { team in
            XCTFail("Joining should not have succeeded")
        }.catch { error in
            guard let apiError = error as? APIError, case .invalidGroupTag = apiError.type else {
                XCTFail(String(describing: error))
                return
            }
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testJoinTeamUserAlreadyMember() throws {
        let completion = expectation(description: "Completion")

        stub(groupStorageManager) { stub in
            when(stub.isMember(userId: signedInUser.userId, groupId: team.groupId)).thenReturn(true)
        }

        firstly {
            teamManager.join(team)
        }.done { team in
            XCTFail("Joining should not have succeeded")
        }.catch { error in
            guard case TeamManagerError.userAlreadyMember = error else {
                XCTFail(String(describing: error))
                return
            }
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testLeaveTeamWithoutMeetup() {
        let completion = expectation(description: "Completion")

        stub(groupStorageManager) { stub in
            when(stub.meetupIn(team: team)).thenReturn(nil)
            when(stub.removeTeam(team.groupId)).thenDoNothing()
        }

        stub(groupManager) { stub in
            when(stub.leave(any())).thenReturn(Promise.value("updatedGroupTag"))
        }

        firstly {
            teamManager.leave(team)
        }.done {
            let teamArgumentCaptor = ArgumentCaptor<Group>()
            verify(self.groupManager).leave(teamArgumentCaptor.capture())
            guard let team = teamArgumentCaptor.value else {
                XCTFail("Invalid team left")
                return
            }
            XCTAssertEqual(team.groupId, self.team.groupId, "Invalid team")

            verify(self.groupStorageManager).removeTeam(self.team.groupId)
        }.catch { error in
            XCTFail(String(describing: error))
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testLeaveTeamWithMeetupNotAttending() {
        let completion = expectation(description: "Completion")

        let meetup = Meetup(groupId: GroupId(), groupKey: Data(), owner: signedInUser.userId, joinMode: .open, permissionMode: .everyone, tag: "groupTag", teamId: team.groupId, meetingPoint: nil, locationSharingEnabled: true)
        stub(groupStorageManager) { stub in
            when(stub.meetupIn(team: team)).thenReturn(meetup)
            when(stub.isMember(userId: signedInUser.userId, groupId: meetup.groupId)).thenReturn(false)
            when(stub.removeTeam(team.groupId)).thenDoNothing()
        }

        stub(groupManager) { stub in
            when(stub.leave(any())).thenReturn(Promise.value("updatedGroupTag"))
        }

        firstly {
            teamManager.leave(team)
        }.done {
            let teamArgumentCaptor = ArgumentCaptor<Group>()
            verify(self.groupManager).leave(teamArgumentCaptor.capture())
            guard let team = teamArgumentCaptor.value else {
                XCTFail("Invalid team left")
                return
            }
            XCTAssertEqual(team.groupId, self.team.groupId, "Invalid team")

            verify(self.groupStorageManager).removeTeam(self.team.groupId)
        }.catch { error in
            XCTFail(String(describing: error))
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testLeaveTeamWithMeetupAttending() {
        let completion = expectation(description: "Completion")

        let meetup = Meetup(groupId: GroupId(), groupKey: Data(), owner: signedInUser.userId, joinMode: .open, permissionMode: .everyone, tag: "groupTag", teamId: team.groupId, meetingPoint: nil, locationSharingEnabled: true)
        stub(groupStorageManager) { stub in
            when(stub.meetupIn(team: team)).thenReturn(meetup)
            when(stub.isMember(userId: signedInUser.userId, groupId: meetup.groupId)).thenReturn(true)
            when(stub.removeTeam(team.groupId)).thenDoNothing()
        }

        stub(groupManager) { stub in
            when(stub.leave(any())).thenReturn(Promise.value("updatedGroupTag"))
        }

        firstly {
            teamManager.leave(team)
        }.done {
            let teamArgumentCaptor = ArgumentCaptor<Group>()
            verify(self.groupManager, times(2)).leave(teamArgumentCaptor.capture())
            XCTAssertEqual(teamArgumentCaptor.allValues[0].groupId, meetup.groupId, "Invalid team")
            XCTAssertEqual(teamArgumentCaptor.allValues[1].groupId, self.team.groupId, "Invalid team")

            verify(self.groupStorageManager).removeTeam(self.team.groupId)
        }.catch { error in
            XCTFail(String(describing: error))
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testDeleteTeamWithMeetup() {
        let completion = expectation(description: "Completion")

        let meetup = Meetup(groupId: GroupId(), groupKey: Data(), owner: signedInUser.userId, joinMode: .open, permissionMode: .everyone, tag: "groupTag", teamId: team.groupId, meetingPoint: nil, locationSharingEnabled: true)
        stub(groupStorageManager) { stub in
            when(stub.meetupIn(team: team)).thenReturn(meetup)
        }

        stub(groupManager) { stub in
            when(stub.leave(any())).thenReturn(Promise.value("updatedGroupTag"))
        }

        firstly {
            teamManager.delete(team)
        }.done {
            XCTFail("Deleting team should not have succeeded")
        }.catch { error in
            guard case TeamManagerError.meetupExisting = error else {
                XCTFail(String(describing: error))
                return
            }
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testDeleteTeamWithoutMeetup() {
        let completion = expectation(description: "Completion")

        stub(groupStorageManager) { stub in
            when(stub.meetupIn(team: team)).thenReturn(nil)
            when(stub.loadMembership(userId: signedInUser.userId, groupId: team.groupId)).thenReturn(membership)
            when(stub.removeTeam(team.groupId)).thenDoNothing()
        }

        let notificationRecipient = NotificationRecipient(userId: UserId(), serverSignedMembershipCertificate: "certificate", priority: .alert)
        stub(groupManager) { stub in
            when(stub.notificationRecipients(groupId: team.groupId, alert: true)).thenReturn([notificationRecipient])
        }

        stub(backend) { stub in
            when(stub.deleteGroup(groupId: team.groupId, serverSignedAdminCertificate: membership.serverSignedMembershipCertificate, groupTag: team.tag, notificationRecipients: [notificationRecipient])).thenReturn(Promise())
        }

        firstly {
            teamManager.delete(team)
        }.done {
            verify(self.groupStorageManager).removeTeam(self.team.groupId)
        }.catch { error in
            XCTFail(String(describing: error))
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testDeleteTeamNotAdmin() {
        let completion = expectation(description: "Completion")

        let notAdminMembership = Membership(userId: signedInUser.userId, publicSigningKey: Data(), groupId: team.groupId, admin: false, selfSignedMembershipCertificate: membership.selfSignedMembershipCertificate, serverSignedMembershipCertificate: membership.serverSignedMembershipCertificate, adminSignedMembershipCertificate: nil)
        stub(groupStorageManager) { stub in
                        when(stub.meetupIn(team: team)).thenReturn(nil)
            when(stub.loadMembership(userId: signedInUser.userId, groupId: team.groupId)).thenReturn(notAdminMembership)
        }

        firstly {
            teamManager.delete(team)
        }.done {
            XCTFail("Deleting team should not have succeeded")
        }.catch { error in
            guard case TeamManagerError.notAdmin = error else {
                XCTFail(String(describing: error))
                return
            }
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testDeleteGroupMemberNoMeetup() {
        let completion = expectation(description: "Completion")

        let updatedGroupTag = "updatedGroupTag"
        let membershipToDelete = Membership(userId: UserId(), publicSigningKey: Data(), groupId: team.groupId, admin: false, selfSignedMembershipCertificate: "certificate", serverSignedMembershipCertificate: "certificate", adminSignedMembershipCertificate: nil)
        
        stub(groupStorageManager) { stub in
            when(stub.loadMembership(userId: signedInUser.userId, groupId: team.groupId)).thenReturn(membership)
            when(stub.meetupIn(team: team)).thenReturn(nil)
            when(stub.removeMembership(userId: membershipToDelete.userId, groupId: team.groupId, updatedGroupTag: updatedGroupTag)).thenDoNothing()
        }
        
        stub(groupManager) { stub in
            when(stub.deleteGroupMember(membershipToDelete, from: any(), serverSignedMembershipCertificate: membership.serverSignedMembershipCertificate)).thenReturn(Promise())
        }

        firstly {
            teamManager.deleteGroupMember(membershipToDelete, from: team)
        }.done {
            let teamArgumentCaptor = ArgumentCaptor<Group>()
            verify(self.groupManager).deleteGroupMember(membershipToDelete, from: teamArgumentCaptor.capture(), serverSignedMembershipCertificate: self.membership.serverSignedMembershipCertificate)
            guard let team = teamArgumentCaptor.value else {
                XCTFail("Invalid team left")
                return
            }
            XCTAssertEqual(team.groupId, self.team.groupId, "Invalid team")
        }.catch { error in
            XCTFail(String(describing: error))
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testDeleteGroupMemberMeetupNotAttending() {
        let completion = expectation(description: "Completion")

        let meetup = Meetup(groupId: GroupId(), groupKey: Data(), owner: signedInUser.userId, joinMode: .open, permissionMode: .everyone, tag: "groupTag", teamId: team.groupId, meetingPoint: nil, locationSharingEnabled: true)
        let membershipToDelete = Membership(userId: UserId(), publicSigningKey: Data(), groupId: team.groupId, admin: false, selfSignedMembershipCertificate: "certificate", serverSignedMembershipCertificate: "certificate", adminSignedMembershipCertificate: nil)
        let updatedGroupTag = "updatedGroupTag"
        stub(groupStorageManager) { stub in
            when(stub.loadMembership(userId: signedInUser.userId, groupId: team.groupId)).thenReturn(membership)
            when(stub.meetupIn(team: team)).thenReturn(meetup)
            when(stub.isMember(userId: membershipToDelete.userId, groupId: team.groupId)).thenReturn(false)
            when(stub.removeMembership(userId: membershipToDelete.userId, groupId: team.groupId, updatedGroupTag: updatedGroupTag)).thenDoNothing()
        }

        stub(groupManager) { stub in
            when(stub.deleteGroupMember(membershipToDelete, from: any(), serverSignedMembershipCertificate: membership.serverSignedMembershipCertificate)).thenReturn(Promise())
        }

        firstly {
            teamManager.deleteGroupMember(membershipToDelete, from: team)
        }.done {
            let teamArgumentCaptor = ArgumentCaptor<Group>()
            verify(self.groupManager).deleteGroupMember(membershipToDelete, from: teamArgumentCaptor.capture(), serverSignedMembershipCertificate: self.membership.serverSignedMembershipCertificate)
            guard let team = teamArgumentCaptor.value else {
                XCTFail("Invalid team left")
                return
            }
            XCTAssertEqual(team.groupId, self.team.groupId, "Invalid team")
        }.catch { error in
            XCTFail(String(describing: error))
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testDeleteGroupMemberMeetupAttendingNotMeetupAdmin() {
        let completion = expectation(description: "Completion")

        let meetup = Meetup(groupId: GroupId(), groupKey: Data(), owner: signedInUser.userId, joinMode: .open, permissionMode: .everyone, tag: "groupTag", teamId: team.groupId, meetingPoint: nil, locationSharingEnabled: true)
        let teamMembershipToDelete = Membership(userId: UserId(), publicSigningKey: Data(), groupId: team.groupId, admin: false, selfSignedMembershipCertificate: "certificate", serverSignedMembershipCertificate: "certificate", adminSignedMembershipCertificate: nil)
        let meetupMembershipToDelete = Membership(userId: teamMembershipToDelete.userId, publicSigningKey: Data(), groupId: meetup.groupId, admin: false, selfSignedMembershipCertificate: "certificate", serverSignedMembershipCertificate: "certificate", adminSignedMembershipCertificate: nil)
        let updatedTeamTag = "updatedTeamTag"
        let updatedMeetupTag = "updatedMeetupTag"

        stub(groupStorageManager) { stub in
            when(stub.loadMembership(userId: signedInUser.userId, groupId: team.groupId)).thenReturn(membership)
            when(stub.loadMembership(userId: meetupMembershipToDelete.userId, groupId: meetup.groupId)).thenReturn(meetupMembershipToDelete)
            when(stub.meetupIn(team: team)).thenReturn(meetup)
            when(stub.isMember(userId: teamMembershipToDelete.userId, groupId: team.groupId)).thenReturn(true)
            when(stub.removeMembership(userId: teamMembershipToDelete.userId, groupId: team.groupId, updatedGroupTag: updatedTeamTag)).thenDoNothing()
            when(stub.removeMembership(userId: meetupMembershipToDelete.userId, groupId: meetup.groupId, updatedGroupTag: updatedMeetupTag)).thenDoNothing()
        }

        stub(groupManager) { stub in
            when(stub.deleteGroupMember(meetupMembershipToDelete, from: any(), serverSignedMembershipCertificate: membership.serverSignedMembershipCertificate)).thenReturn(Promise())
            when(stub.deleteGroupMember(teamMembershipToDelete, from: any(), serverSignedMembershipCertificate: membership.serverSignedMembershipCertificate)).thenReturn(Promise())
        }

        firstly {
            teamManager.deleteGroupMember(teamMembershipToDelete, from: team)
        }.done {
            let membershipArgumentCaptor = ArgumentCaptor<Membership>()
            let groupArgumentCaptor = ArgumentCaptor<Group>()
            verify(self.groupManager, times(2)).deleteGroupMember(membershipArgumentCaptor.capture(), from: groupArgumentCaptor.capture(), serverSignedMembershipCertificate: self.membership.serverSignedMembershipCertificate)

            XCTAssertEqual(membershipArgumentCaptor.allValues[0], meetupMembershipToDelete, "Invalid membership")
            XCTAssertEqual(membershipArgumentCaptor.allValues[1], teamMembershipToDelete, "Invalid membership")

            XCTAssertEqual(groupArgumentCaptor.allValues[0].groupId, meetup.groupId, "Invalid membership")
            XCTAssertEqual(groupArgumentCaptor.allValues[1].groupId, self.team.groupId, "Invalid membership")
        }.catch { error in
            XCTFail(String(describing: error))
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testDeleteGroupMemberNotAdmin() {
        let completion = expectation(description: "Completion")

        let notAdminMembership = Membership(userId: signedInUser.userId, publicSigningKey: Data(), groupId: team.groupId, admin: false, selfSignedMembershipCertificate: membership.selfSignedMembershipCertificate, serverSignedMembershipCertificate: membership.serverSignedMembershipCertificate, adminSignedMembershipCertificate: nil)
        stub(groupStorageManager) { stub in
            when(stub.loadMembership(userId: signedInUser.userId, groupId: team.groupId)).thenReturn(notAdminMembership)
        }

        firstly {
            teamManager.deleteGroupMember(membership, from: team)
        }.done {
            XCTFail("Deleting team member should not have succeeded")
        }.catch { error in
            guard case TeamManagerError.notAdmin = error else {
                XCTFail(String(describing: error))
                return
            }
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testSetTeamName() throws {
        let completion = expectation(description: "Completion")

        let updatedTeamTag = "updatedTeamTag"
        let updatedName = "updatedTeamName"
        let updatedSettings = GroupSettings(owner: team.owner, name: updatedName)
        let updatedSettingsData = try encoder.encode(updatedSettings)
        let encryptedSettings = "encryptedSettings".data

        stub(cryptoManager) { stub in
            when(stub.encrypt(updatedSettingsData, secretKey: team.groupKey)).thenReturn(encryptedSettings)
        }

        stub(groupStorageManager) { stub in
            when(stub.loadMembership(userId: signedInUser.userId, groupId: team.groupId)).thenReturn(membership)
            when(stub.updateTeamName(groupId: team.groupId, name: updatedName, tag: updatedTeamTag)).thenDoNothing()
        }

        let notificationRecipient = NotificationRecipient(userId: UserId(), serverSignedMembershipCertificate: "certificate", priority: .alert)
        stub(groupManager) { stub in
            when(stub.notificationRecipients(groupId: team.groupId, alert: true)).thenReturn([notificationRecipient])
        }

        let updatedEtagResponse = UpdatedEtagResponse(groupTag: updatedTeamTag)
        stub(backend) { stub in
            when(stub.updateSettings(groupId: team.groupId, encryptedSettings: encryptedSettings, serverSignedMembershipCertificate: membership.serverSignedMembershipCertificate, groupTag: team.tag, notificationRecipients: [notificationRecipient])).thenReturn(Promise.value(updatedEtagResponse))
        }

        firstly {
            teamManager.setTeamName(team: team, name: updatedName)
        }.done {
            verify(self.groupStorageManager).updateTeamName(groupId: self.team.groupId, name: updatedName, tag: updatedTeamTag)
        }.catch { error in
            XCTFail(String(describing: error))
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testSendToAllTeams() {
        let completion = expectation(description: "Completion")

        stub(groupStorageManager) { stub in
            when(stub.loadTeams()).thenReturn(Array(repeating: team, count: 2))
        }

        let payloadContainer = PayloadContainer(payloadType: .resetConversationV1, payload: ResetConversation())
        stub(groupManager) { stub in
            when(stub.send(payloadContainer: payloadContainer, to: any(), collapseId: nil as Envelope.CollapseIdentifier?, priority: MessagePriority.background)).thenReturn(Promise())
        }

        firstly {
            teamManager.sendToAllTeams(payloadContainer: payloadContainer)
        }.done { a in

            let teamArgumentCaptor = ArgumentCaptor<Group>()
            verify(self.groupManager, times(2)).send(payloadContainer: payloadContainer, to: teamArgumentCaptor.capture(), collapseId: nil as Envelope.CollapseIdentifier?, priority: MessagePriority.background)

            XCTAssertEqual(teamArgumentCaptor.allValues[0].groupId, self.team.groupId, "Invalid team")
            XCTAssertEqual(teamArgumentCaptor.allValues[1].groupId, self.team.groupId, "Invalid team")
        }.catch { error in
            XCTFail(String(describing: error))
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }
}
