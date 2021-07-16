//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels
import Shouter
import XCTest
import PromiseKit
import Cuckoo
import CoreLocation

@testable import TICE

class MeetupManagerTests: XCTestCase {

    var groupManager: MockGroupManagerType!
    var groupStorageManager: MockGroupStorageManagerType!
    var cryptoManager: MockCryptoManagerType!
    var authManager: MockAuthManagerType!
    var locationManager: MockLocationManagerType!
    var backend: MockTICEAPI!
    var signedInUser: SignedInUser!
    var encoder: JSONEncoder!
    var decoder: JSONDecoder!
    var notifier: Notifier!
    var tracker: TrackerType!

    var meetupManager: MeetupManager!

    var team: Team!
    var meetup: Meetup!

    override func setUp() {
        super.setUp()

        groupManager = MockGroupManagerType()
        groupStorageManager = MockGroupStorageManagerType()
        cryptoManager = MockCryptoManagerType()
        authManager = MockAuthManagerType()
        locationManager = MockLocationManagerType()
        backend = MockTICEAPI()
        tracker = MockTracker()
        signedInUser = SignedInUser(userId: UserId(), privateSigningKey: Data(), publicSigningKey: Data(), publicName: nil)
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        notifier = Shouter()

        team = Team(groupId: GroupId(), groupKey: "teamKey".data, owner: signedInUser.userId, joinMode: .open, permissionMode: .everyone, tag: "teamTag", url: URL(string: "https://develop.tice.app/group/1")!, name: nil, meetupId: nil)
        meetup = Meetup(groupId: GroupId(), groupKey: "meetupKey".data, owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "meetupTag", teamId: team.groupId, meetingPoint: nil, locationSharingEnabled: true)

        stub(locationManager) { stub in
            when(stub.delegate.set(any())).thenDoNothing()
        }
        meetupManager = MeetupManager(groupManager: groupManager, groupStorageManager: groupStorageManager, signedInUser: signedInUser, cryptoManager: cryptoManager, authManager: authManager, locationManager: locationManager, backend: backend, encoder: encoder, decoder: decoder, tracker: tracker, reloadTimeout: 60.0)
    }

    func testGetMeetup() {
        stub(groupStorageManager) { stub in
            when(stub.loadMeetup(any())).thenReturn(nil)
            when(stub.loadMeetup(meetup.groupId)).thenReturn(meetup)
        }

        XCTAssertEqual(meetupManager.meetupWith(groupId: meetup.groupId)?.groupId, meetup.groupId, "Invalid meetup")
        XCTAssertNil(meetupManager.meetupWith(groupId: GroupId())?.groupId, "Invalid meetup")
    }

    func testCreateMeetupInTeamWithMeetup() {
        let completion = expectation(description: "Completion")

        let meetupKey = "meetupKey".data
        stub(cryptoManager) { stub in
            when(stub.generateGroupKey()).thenReturn(meetupKey)
        }

        stub(groupStorageManager) { stub in
            when(stub.meetupIn(team: team)).thenReturn(meetup)
        }

        firstly {
            meetupManager.createMeetup(in: team, at: nil, joinMode: .open, permissionMode: .everyone)
        }.done { _ in
            XCTFail("Creating meetup should not have succeeded")
        }.catch { error in
            guard case MeetupManagerError.meetupAlreadyRunning = error else {
                XCTFail(String(describing: error))
                return
            }
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testCreateMeetup() throws {
        let completion = expectation(description: "Completion")

        let meetupKey = "meetupKey".data
        let meetupSettings = GroupSettings(owner: signedInUser.userId, name: nil)
        let meetupSettingsData = try encoder.encode(meetupSettings)
        let encryptedMeetupSettings = "encryptedMeetupSettings".data

        let meetingPoint = Location(latitude: 52.0, longitude: 13.0)
        let internalMeetupSettings = InternalMeetupSettings(location: meetingPoint)
        let internalMeetupSettingsData = try encoder.encode(internalMeetupSettings)
        let encryptedInternalSettings = "encryptedInternalMeetupSettings".data

        let parentEncryptedChildGroupKey = "parentEncryptedChildGroupKey".data

        stub(cryptoManager) { stub in
            when(stub.generateGroupKey()).thenReturn(meetupKey)
            when(stub.encrypt(meetupSettingsData, secretKey: meetupKey)).thenReturn(encryptedMeetupSettings)
            when(stub.encrypt(internalMeetupSettingsData, secretKey: meetupKey)).thenReturn(encryptedInternalSettings)
            when(stub.encrypt(meetupKey, secretKey: team.groupKey)).thenReturn(parentEncryptedChildGroupKey)
        }
        
        let selfSignedAdminCertificate = "selfSignedAdminCertificate"
        
        stub(authManager) { stub in
            when(stub.createUserSignedMembershipCertificate(userId: signedInUser.userId, groupId: any(), admin: true, issuerUserId: signedInUser.userId, signingKey: signedInUser.privateSigningKey)).thenReturn(selfSignedAdminCertificate)
        }

        let groupTagAfterAddingMember = "meetupTag2"
        stub(groupStorageManager) { stub in
            when(stub.meetupIn(team: team)).thenReturn(nil)
            when(stub.storeMeetup(any(Meetup.self))).thenDoNothing()
            when(stub.store(any(Membership.self))).thenDoNothing()
        }

        let parentGroup = ParentGroup(groupId: team.groupId, encryptedChildGroupKey: parentEncryptedChildGroupKey)

        let meetupURL = URL(string: "https://develop.tice.app/group/2")!
        let serverSignedAdminCertificate = "serverSignedAdminCertificate"
        let groupTagAfterCreating = "meetupTag1"
        let createGroupResponse = CreateGroupResponse(url: meetupURL, serverSignedAdminCertificate: serverSignedAdminCertificate, groupTag: groupTagAfterCreating)

        stub(backend) { stub in
            when(stub.createGroup(userId: signedInUser.userId, type: GroupType.meetup, joinMode: JoinMode.open, permissionMode: PermissionMode.everyone, groupId: any(), parentGroup: parentGroup, selfSignedAdminCertificate: selfSignedAdminCertificate, encryptedSettings: encryptedMeetupSettings, encryptedInternalSettings: encryptedInternalSettings)).thenReturn(Promise.value(createGroupResponse))
        }

        stub(groupManager) { stub in
            when(stub.addUserMember(into: any(), admin: true, serverSignedMembershipCertificate: serverSignedAdminCertificate)).then { meetup, _, _ -> Promise<(Membership, GroupTag)> in
                let membership = Membership(userId: self.signedInUser.userId, publicSigningKey: self.signedInUser.publicSigningKey, groupId: meetup.groupId, admin: true, selfSignedMembershipCertificate: selfSignedAdminCertificate, serverSignedMembershipCertificate: serverSignedAdminCertificate, adminSignedMembershipCertificate: selfSignedAdminCertificate)
                return Promise.value((membership, groupTagAfterAddingMember))
            }
            when(stub.sendGroupUpdateNotification(to: any(), action: GroupUpdate.Action.childGroupCreated)).thenReturn(Promise())
        }

        firstly {
            meetupManager.createMeetup(in: team, at: meetingPoint, joinMode: .open, permissionMode: .everyone)
        }.done { _ in
            let meetupArgumentCaptor = ArgumentCaptor<Meetup>()
            verify(self.groupStorageManager).storeMeetup(meetupArgumentCaptor.capture())
            guard let storedMeetup = meetupArgumentCaptor.value else {
                XCTFail("Invalid meetup stored")
                return
            }

            XCTAssertEqual(storedMeetup.joinMode, .open, "Invalid group")
            XCTAssertEqual(storedMeetup.permissionMode, .everyone, "Invalid group")
            XCTAssertEqual(storedMeetup.groupKey, meetupKey, "Invalid group")
            XCTAssertEqual(storedMeetup.owner, self.signedInUser.userId, "Invalid group")
            XCTAssertEqual(storedMeetup.tag, groupTagAfterAddingMember, "Invalid group")

            let membershipCheck = Membership(userId: self.signedInUser.userId, publicSigningKey: self.signedInUser.publicSigningKey, groupId: storedMeetup.groupId, admin: true, selfSignedMembershipCertificate: selfSignedAdminCertificate, serverSignedMembershipCertificate: serverSignedAdminCertificate, adminSignedMembershipCertificate: selfSignedAdminCertificate)
            verify(self.groupStorageManager).store(membershipCheck)

            let teamArgumentCaptor = ArgumentCaptor<Group>()
            verify(self.groupManager).sendGroupUpdateNotification(to: teamArgumentCaptor.capture(), action: GroupUpdate.Action.childGroupCreated)
            guard let team = teamArgumentCaptor.value as? Team else {
                XCTFail("Invalid team")
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

    func testReloadModifiedMeetupParticipating() throws {
        let completion = expectation(description: "Completion")

        let selfSignedCertificate = "selfSignedCertificate"
        let serverSignedCertificate = "serverSignedCertificate"
        let membership = Membership(userId: signedInUser.userId, publicSigningKey: signedInUser.publicSigningKey, groupId: meetup.groupId, admin: true, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedMembershipCertificate: serverSignedCertificate, adminSignedMembershipCertificate: selfSignedCertificate)

        stub(groupStorageManager) { stub in
            when(stub.isMember(userId: signedInUser.userId, groupId: meetup.groupId)).thenReturn(true)
            when(stub.loadMembership(userId: signedInUser.userId, groupId: meetup.groupId)).thenReturn(membership)
            when(stub.storeMeetup(any())).thenDoNothing()
            when(stub.store([membership], for: meetup.groupId)).thenDoNothing()
            when(stub.loadMeetup(meetup.groupId)).thenReturn(meetup)
        }

        let meetupSettings = GroupSettings(owner: signedInUser.userId, name: nil)
        let meetupSettingsData = try encoder.encode(meetupSettings)
        let encryptedMeetupSettings = "encryptedMeetupSettings".data

        let location = Location(latitude: 52.0, longitude: 13.0)
        let internalMeetupSettings = InternalMeetupSettings(location: location)
        let internalMeetupSettingsData = try encoder.encode(internalMeetupSettings)
        let encryptedInternalSettings = "encryptedInternalMeetupSettings".data

        let membershipData = try encoder.encode(membership)
        let encryptedMembership = "encryptedMembership".data

        let parentEncryptedGroupKey = "parentEncryptedGroupKey".data

        let updatedMeetupTag = "updatedMeetupTag"

        let groupInternalsResponse = GroupInternalsResponse(groupId: meetup.groupId, parentGroupId: team.groupId, type: .meetup, joinMode: .open, permissionMode: .everyone, url: URL(string: "https://develop.tice.app/group/2")!, encryptedSettings: encryptedMeetupSettings, encryptedInternalSettings: encryptedInternalSettings, encryptedMemberships: [encryptedMembership], parentEncryptedGroupKey: parentEncryptedGroupKey, children: [], groupTag: updatedMeetupTag)

        stub(backend) { stub in
            when(stub.getGroupInternals(groupId: meetup.groupId, serverSignedMembershipCertificate: serverSignedCertificate, groupTag: meetup.tag)).thenReturn(Promise.value(groupInternalsResponse))
        }

        stub(cryptoManager) { stub in
            when(stub.decrypt(encryptedData: encryptedMeetupSettings, secretKey: meetup.groupKey)).thenReturn(meetupSettingsData)
            when(stub.decrypt(encryptedData: encryptedInternalSettings, secretKey: meetup.groupKey)).thenReturn(internalMeetupSettingsData)
            when(stub.decrypt(encryptedData: encryptedMembership, secretKey: meetup.groupKey)).thenReturn(membershipData)
        }

        firstly {
            meetupManager.reload(meetup: meetup)
        }.done { reloadedMeetup in
            XCTAssertNotEqual(reloadedMeetup.tag, self.meetup.tag, "Meetup should have been reloaded")
            
            let meetupArgumentCaptor = ArgumentCaptor<Meetup>()
            verify(self.groupStorageManager).storeMeetup(meetupArgumentCaptor.capture())
            guard let storedMeetup = meetupArgumentCaptor.value else {
                XCTFail("Invalid meetup stored")
                return
            }

            XCTAssertEqual(storedMeetup.joinMode, .open, "Invalid group")
            XCTAssertEqual(storedMeetup.permissionMode, .everyone, "Invalid group")
            XCTAssertEqual(storedMeetup.groupKey, self.meetup.groupKey, "Invalid group")
            XCTAssertEqual(storedMeetup.owner, self.signedInUser.userId, "Invalid group")
            XCTAssertEqual(storedMeetup.tag, updatedMeetupTag, "Invalid group")

            let membershipCheck = Membership(userId: self.signedInUser.userId, publicSigningKey: self.signedInUser.publicSigningKey, groupId: storedMeetup.groupId, admin: true, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedMembershipCertificate: serverSignedCertificate, adminSignedMembershipCertificate: selfSignedCertificate)
            verify(self.groupStorageManager).store([membershipCheck], for: self.meetup.groupId)
        }.catch { error in
            XCTFail(String(describing: error))
        }.finally {
            completion.fulfill()
        }
        
        wait(for: [completion])
    }

    func testReloadModifiedMeetupNotParticipating() throws {
        let completion = expectation(description: "Completion")

        let selfSignedCertificate = "selfSignedCertificate"
        let serverSignedCertificate = "serverSignedCertificate"
        let meetupMembership = Membership(userId: signedInUser.userId, publicSigningKey: signedInUser.publicSigningKey, groupId: meetup.groupId, admin: true, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedMembershipCertificate: serverSignedCertificate, adminSignedMembershipCertificate: selfSignedCertificate)
        let teamMembership = Membership(userId: signedInUser.userId, publicSigningKey: signedInUser.publicSigningKey, groupId: team.groupId, admin: true, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedMembershipCertificate: serverSignedCertificate, adminSignedMembershipCertificate: selfSignedCertificate)

        stub(groupStorageManager) { stub in
            when(stub.isMember(userId: signedInUser.userId, groupId: meetup.groupId)).thenReturn(false)
            when(stub.loadMembership(userId: signedInUser.userId, groupId: team.groupId)).thenReturn(teamMembership)
            when(stub.storeMeetup(any())).thenDoNothing()
            when(stub.store([meetupMembership], for: meetup.groupId)).thenDoNothing()
            when(stub.loadMeetup(meetup.groupId)).thenReturn(meetup)
        }

        let meetupSettings = GroupSettings(owner: signedInUser.userId, name: nil)
        let meetupSettingsData = try encoder.encode(meetupSettings)
        let encryptedMeetupSettings = "encryptedMeetupSettings".data

        let location = Location(latitude: 52.0, longitude: 13.0)
        let internalMeetupSettings = InternalMeetupSettings(location: location)
        let internalMeetupSettingsData = try encoder.encode(internalMeetupSettings)
        let encryptedInternalSettings = "encryptedInternalMeetupSettings".data

        let membershipData = try encoder.encode(meetupMembership)
        let encryptedMembership = "encryptedMembership".data

        let parentEncryptedGroupKey = "parentEncryptedGroupKey".data

        let updatedMeetupTag = "updatedMeetupTag"

        let groupInternalsResponse = GroupInternalsResponse(groupId: meetup.groupId, parentGroupId: team.groupId, type: .meetup, joinMode: .open, permissionMode: .everyone, url: URL(string: "https://develop.tice.app/group/2")!, encryptedSettings: encryptedMeetupSettings, encryptedInternalSettings: encryptedInternalSettings, encryptedMemberships: [encryptedMembership], parentEncryptedGroupKey: parentEncryptedGroupKey, children: [], groupTag: updatedMeetupTag)

        stub(backend) { stub in
            when(stub.getGroupInternals(groupId: meetup.groupId, serverSignedMembershipCertificate: serverSignedCertificate, groupTag: meetup.tag)).thenReturn(Promise.value(groupInternalsResponse))
        }

        stub(cryptoManager) { stub in
            when(stub.decrypt(encryptedData: encryptedMeetupSettings, secretKey: meetup.groupKey)).thenReturn(meetupSettingsData)
            when(stub.decrypt(encryptedData: encryptedInternalSettings, secretKey: meetup.groupKey)).thenReturn(internalMeetupSettingsData)
            when(stub.decrypt(encryptedData: encryptedMembership, secretKey: meetup.groupKey)).thenReturn(membershipData)
        }

        firstly {
            meetupManager.reload(meetup: meetup)
        }.done { reloadedMeetup in
            XCTAssertNotEqual(reloadedMeetup.tag, self.meetup.tag, "Meetup should have been reloaded")

            let meetupArgumentCaptor = ArgumentCaptor<Meetup>()
            verify(self.groupStorageManager).storeMeetup(meetupArgumentCaptor.capture())
            guard let storedMeetup = meetupArgumentCaptor.value else {
                XCTFail("Invalid meetup stored")
                return
            }

            XCTAssertEqual(storedMeetup.joinMode, .open, "Invalid group")
            XCTAssertEqual(storedMeetup.permissionMode, .everyone, "Invalid group")
            XCTAssertEqual(storedMeetup.groupKey, self.meetup.groupKey, "Invalid group")
            XCTAssertEqual(storedMeetup.owner, self.signedInUser.userId, "Invalid group")
            XCTAssertEqual(storedMeetup.tag, updatedMeetupTag, "Invalid group")

            let membershipCheck = Membership(userId: self.signedInUser.userId, publicSigningKey: self.signedInUser.publicSigningKey, groupId: storedMeetup.groupId, admin: true, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedMembershipCertificate: serverSignedCertificate, adminSignedMembershipCertificate: selfSignedCertificate)
            verify(self.groupStorageManager).store([membershipCheck], for: self.meetup.groupId)
        }.catch { error in
            XCTFail(String(describing: error))
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testReloadNotModifiedMeetup() throws {
        let completion = expectation(description: "Completion")

        let selfSignedCertificate = "selfSignedCertificate"
        let serverSignedCertificate = "serverSignedCertificate"
        let teamMembership = Membership(userId: signedInUser.userId, publicSigningKey: signedInUser.publicSigningKey, groupId: team.groupId, admin: true, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedMembershipCertificate: serverSignedCertificate, adminSignedMembershipCertificate: selfSignedCertificate)

        stub(groupStorageManager) { stub in
            when(stub.isMember(userId: signedInUser.userId, groupId: meetup.groupId)).thenReturn(false)
            when(stub.loadMembership(userId: signedInUser.userId, groupId: team.groupId)).thenReturn(teamMembership)
        }

        stub(backend) { stub in
            when(stub.getGroupInternals(groupId: meetup.groupId, serverSignedMembershipCertificate: serverSignedCertificate, groupTag: meetup.tag)).thenReturn(Promise(error: BackendError.notModified))
        }

        firstly {
            meetupManager.reload(meetup: meetup)
        }.done { reloadedMeetup in
            XCTAssertEqual(reloadedMeetup.tag, self.meetup.tag, "Meetup should not have been reloaded")
        }.catch { error in
            XCTFail(String(describing: error))
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testReloadMeetupNotFound() throws {
        let completion = expectation(description: "Completion")

        let selfSignedCertificate = "selfSignedCertificate"
        let serverSignedCertificate = "serverSignedCertificate"
        let teamMembership = Membership(userId: signedInUser.userId, publicSigningKey: signedInUser.publicSigningKey, groupId: team.groupId, admin: true, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedMembershipCertificate: serverSignedCertificate, adminSignedMembershipCertificate: selfSignedCertificate)

        stub(groupStorageManager) { stub in
            when(stub.isMember(userId: signedInUser.userId, groupId: meetup.groupId)).thenReturn(false)
            when(stub.loadMembership(userId: signedInUser.userId, groupId: team.groupId)).thenReturn(teamMembership)
            when(stub.removeMeetup(meetup: any())).thenDoNothing()
        }

        stub(backend) { stub in
            when(stub.getGroupInternals(groupId: meetup.groupId, serverSignedMembershipCertificate: serverSignedCertificate, groupTag: meetup.tag)).thenReturn(Promise(error: APIError(type: .notFound)))
        }

        firstly {
            meetupManager.reload(meetup: meetup)
        }.done { _ in
            XCTFail("Meetup should not have been reloaded")
        }.catch { error in
            guard let apiError = error as? APIError, apiError.type == .notFound else {
                XCTFail(String(describing: error))
                return
            }
            let meetupArgumentCaptor = ArgumentCaptor<Meetup>()
            verify(self.groupStorageManager).removeMeetup(meetup: meetupArgumentCaptor.capture())
            guard let removedMeetup = meetupArgumentCaptor.value else {
                XCTFail("Invalid meetup stored")
                return
            }
            XCTAssertEqual(removedMeetup.groupId, self.meetup.groupId, "Invalid meetup")
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testReloadMeetupUnauthorized() throws {
        let completion = expectation(description: "Completion")

        let selfSignedCertificate = "selfSignedCertificate"
        let serverSignedCertificate = "serverSignedCertificate"
        let teamMembership = Membership(userId: signedInUser.userId, publicSigningKey: signedInUser.publicSigningKey, groupId: team.groupId, admin: true, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedMembershipCertificate: serverSignedCertificate, adminSignedMembershipCertificate: selfSignedCertificate)

        stub(groupStorageManager) { stub in
            when(stub.isMember(userId: signedInUser.userId, groupId: meetup.groupId)).thenReturn(false)
            when(stub.loadMembership(userId: signedInUser.userId, groupId: team.groupId)).thenReturn(teamMembership)
            when(stub.removeMeetup(meetup: any())).thenDoNothing()
        }

        stub(backend) { stub in
            when(stub.getGroupInternals(groupId: meetup.groupId, serverSignedMembershipCertificate: serverSignedCertificate, groupTag: meetup.tag)).thenReturn(Promise(error: BackendError.unauthorized))
        }

        firstly {
            meetupManager.reload(meetup: meetup)
        }.done { _ in
            XCTFail("Meetup should not have been reloaded")
        }.catch { error in
            guard case BackendError.unauthorized = error else {
                XCTFail(String(describing: error))
                return
            }
            let meetupArgumentCaptor = ArgumentCaptor<Meetup>()
            verify(self.groupStorageManager).removeMeetup(meetup: meetupArgumentCaptor.capture())
            guard let removedMeetup = meetupArgumentCaptor.value else {
                XCTFail("Invalid meetup stored")
                return
            }
            XCTAssertEqual(removedMeetup.groupId, self.meetup.groupId, "Invalid meetup")
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testAddOrReloadKnownMeetup() throws {
        let completion = expectation(description: "Completion")

        let selfSignedCertificate = "selfSignedCertificate"
        let serverSignedCertificate = "serverSignedCertificate"
        let membership = Membership(userId: signedInUser.userId, publicSigningKey: signedInUser.publicSigningKey, groupId: meetup.groupId, admin: true, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedMembershipCertificate: serverSignedCertificate, adminSignedMembershipCertificate: selfSignedCertificate)

        stub(groupStorageManager) { stub in
            when(stub.isMember(userId: signedInUser.userId, groupId: meetup.groupId)).thenReturn(true)
            when(stub.loadMembership(userId: signedInUser.userId, groupId: meetup.groupId)).thenReturn(membership)
            when(stub.storeMeetup(any())).thenDoNothing()
            when(stub.store([membership], for: meetup.groupId)).thenDoNothing()
            when(stub.loadMeetup(meetup.groupId)).thenReturn(meetup)
        }

        let meetupSettings = GroupSettings(owner: signedInUser.userId, name: nil)
        let meetupSettingsData = try encoder.encode(meetupSettings)
        let encryptedMeetupSettings = "encryptedMeetupSettings".data

        let location = Location(latitude: 52.0, longitude: 13.0)
        let internalMeetupSettings = InternalMeetupSettings(location: location)
        let internalMeetupSettingsData = try encoder.encode(internalMeetupSettings)
        let encryptedInternalSettings = "encryptedInternalMeetupSettings".data

        let membershipData = try encoder.encode(membership)
        let encryptedMembership = "encryptedMembership".data

        let parentEncryptedGroupKey = "parentEncryptedGroupKey".data

        let updatedMeetupTag = "updatedMeetupTag"

        let groupInternalsResponse = GroupInternalsResponse(groupId: meetup.groupId, parentGroupId: team.groupId, type: .meetup, joinMode: .open, permissionMode: .everyone, url: URL(string: "https://develop.tice.app/group/2")!, encryptedSettings: encryptedMeetupSettings, encryptedInternalSettings: encryptedInternalSettings, encryptedMemberships: [encryptedMembership], parentEncryptedGroupKey: parentEncryptedGroupKey, children: [], groupTag: updatedMeetupTag)

        stub(backend) { stub in
            when(stub.getGroupInternals(groupId: meetup.groupId, serverSignedMembershipCertificate: serverSignedCertificate, groupTag: meetup.tag)).thenReturn(Promise.value(groupInternalsResponse))
        }

        stub(cryptoManager) { stub in
            when(stub.decrypt(encryptedData: encryptedMeetupSettings, secretKey: meetup.groupKey)).thenReturn(meetupSettingsData)
            when(stub.decrypt(encryptedData: encryptedInternalSettings, secretKey: meetup.groupKey)).thenReturn(internalMeetupSettingsData)
            when(stub.decrypt(encryptedData: encryptedMembership, secretKey: meetup.groupKey)).thenReturn(membershipData)
        }

        firstly {
            meetupManager.addOrReload(meetupId: meetup.groupId, teamId: team.groupId)
        }.done { _ in
            let meetupArgumentCaptor = ArgumentCaptor<Meetup>()
            verify(self.groupStorageManager).storeMeetup(meetupArgumentCaptor.capture())
            guard let storedMeetup = meetupArgumentCaptor.value else {
                XCTFail("Invalid meetup stored")
                return
            }

            XCTAssertEqual(storedMeetup.joinMode, .open, "Invalid group")
            XCTAssertEqual(storedMeetup.permissionMode, .everyone, "Invalid group")
            XCTAssertEqual(storedMeetup.groupKey, self.meetup.groupKey, "Invalid group")
            XCTAssertEqual(storedMeetup.owner, self.signedInUser.userId, "Invalid group")
            XCTAssertEqual(storedMeetup.tag, updatedMeetupTag, "Invalid group")

            let membershipCheck = Membership(userId: self.signedInUser.userId, publicSigningKey: self.signedInUser.publicSigningKey, groupId: storedMeetup.groupId, admin: true, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedMembershipCertificate: serverSignedCertificate, adminSignedMembershipCertificate: selfSignedCertificate)
            verify(self.groupStorageManager).store([membershipCheck], for: self.meetup.groupId)
        }.catch { error in
            XCTFail(String(describing: error))
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testAddOrReloadUnknownMeetup() throws {
        let completion = expectation(description: "Completion")

        let selfSignedCertificate = "selfSignedCertificate"
        let serverSignedCertificate = "serverSignedCertificate"
        let meetupMembership = Membership(userId: signedInUser.userId, publicSigningKey: signedInUser.publicSigningKey, groupId: meetup.groupId, admin: true, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedMembershipCertificate: serverSignedCertificate, adminSignedMembershipCertificate: selfSignedCertificate)
        let teamMembership = Membership(userId: signedInUser.userId, publicSigningKey: signedInUser.publicSigningKey, groupId: team.groupId, admin: true, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedMembershipCertificate: serverSignedCertificate, adminSignedMembershipCertificate: selfSignedCertificate)

        stub(groupStorageManager) { stub in
            when(stub.isMember(userId: signedInUser.userId, groupId: meetup.groupId)).thenReturn(false)
            when(stub.loadMembership(userId: signedInUser.userId, groupId: team.groupId)).thenReturn(teamMembership)
            when(stub.storeMeetup(any())).thenDoNothing()
            when(stub.store([meetupMembership], for: meetup.groupId)).thenDoNothing()
            when(stub.loadMeetup(meetup.groupId)).thenReturn(nil)
            when(stub.loadTeam(team.groupId)).thenReturn(team)
        }

        let meetupSettings = GroupSettings(owner: signedInUser.userId, name: nil)
        let meetupSettingsData = try encoder.encode(meetupSettings)
        let encryptedMeetupSettings = "encryptedMeetupSettings".data

        let location = Location(latitude: 52.0, longitude: 13.0)
        let internalMeetupSettings = InternalMeetupSettings(location: location)
        let internalMeetupSettingsData = try encoder.encode(internalMeetupSettings)
        let encryptedInternalSettings = "encryptedInternalMeetupSettings".data

        let membershipData = try encoder.encode(meetupMembership)
        let encryptedMembership = "encryptedMembership".data

        let parentEncryptedGroupKey = "parentEncryptedGroupKey".data

        let updatedMeetupTag = "updatedMeetupTag"

        let groupInternalsResponse = GroupInternalsResponse(groupId: meetup.groupId, parentGroupId: team.groupId, type: .meetup, joinMode: .open, permissionMode: .everyone, url: URL(string: "https://develop.tice.app/group/2")!, encryptedSettings: encryptedMeetupSettings, encryptedInternalSettings: encryptedInternalSettings, encryptedMemberships: [encryptedMembership], parentEncryptedGroupKey: parentEncryptedGroupKey, children: [], groupTag: updatedMeetupTag)

        stub(backend) { stub in
            when(stub.getGroupInternals(groupId: meetup.groupId, serverSignedMembershipCertificate: serverSignedCertificate, groupTag: meetup.tag)).thenReturn(Promise.value(groupInternalsResponse))
        }

        stub(cryptoManager) { stub in
            when(stub.decrypt(encryptedData: encryptedMeetupSettings, secretKey: meetup.groupKey)).thenReturn(meetupSettingsData)
            when(stub.decrypt(encryptedData: encryptedInternalSettings, secretKey: meetup.groupKey)).thenReturn(internalMeetupSettingsData)
            when(stub.decrypt(encryptedData: encryptedMembership, secretKey: meetup.groupKey)).thenReturn(membershipData)
        }

        firstly {
            meetupManager.reload(meetup: meetup)
        }.done { reloadedMeetup in
            XCTAssertNotEqual(reloadedMeetup.tag, self.meetup.tag, "Meetup should have been reloaded")

            let meetupArgumentCaptor = ArgumentCaptor<Meetup>()
            verify(self.groupStorageManager).storeMeetup(meetupArgumentCaptor.capture())
            guard let storedMeetup = meetupArgumentCaptor.value else {
                XCTFail("Invalid meetup stored")
                return
            }

            XCTAssertEqual(storedMeetup.joinMode, .open, "Invalid group")
            XCTAssertEqual(storedMeetup.permissionMode, .everyone, "Invalid group")
            XCTAssertEqual(storedMeetup.groupKey, self.meetup.groupKey, "Invalid group")
            XCTAssertEqual(storedMeetup.owner, self.signedInUser.userId, "Invalid group")
            XCTAssertEqual(storedMeetup.tag, updatedMeetupTag, "Invalid group")

            let membershipCheck = Membership(userId: self.signedInUser.userId, publicSigningKey: self.signedInUser.publicSigningKey, groupId: storedMeetup.groupId, admin: true, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedMembershipCertificate: serverSignedCertificate, adminSignedMembershipCertificate: selfSignedCertificate)
            verify(self.groupStorageManager).store([membershipCheck], for: self.meetup.groupId)
        }.catch { error in
            XCTFail(String(describing: error))
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testJoinMeetup() {
        let completion = expectation(description: "Completion")

        let selfSignedCertificate = "selfSignedCertificate"
        stub(authManager) { stub in
            when(stub.createUserSignedMembershipCertificate(userId: signedInUser.userId, groupId: any(), admin: false, issuerUserId: signedInUser.userId, signingKey: signedInUser.privateSigningKey)).thenReturn(selfSignedCertificate)
        }

        let serverSignedCertificate = "serverSignedCertificate"
        let joinGroupResponse = JoinGroupResponse(serverSignedMembershipCertificate: serverSignedCertificate)

        stub(backend) { stub in
            when(stub.joinGroup(groupId: meetup.groupId, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedAdminCertificate: nil as Certificate?, adminSignedMembershipCertificate: nil as Certificate?, groupTag: meetup.tag)).thenReturn(Promise.value(joinGroupResponse))
        }

        let membership = Membership(userId: signedInUser.userId, publicSigningKey: signedInUser.publicSigningKey, groupId: meetup.groupId, admin: false, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedMembershipCertificate: serverSignedCertificate, adminSignedMembershipCertificate: nil)
        let updatedMeetupTag = "updatedMeetupTag"

        stub(groupManager) { stub in
            when(stub.addUserMember(into: any(), admin: false, serverSignedMembershipCertificate: serverSignedCertificate)).thenReturn(Promise.value((membership, updatedMeetupTag)))
        }

        stub(groupStorageManager) { stub in
            when(stub.store(any())).thenDoNothing()
            when(stub.updateMeetupTag(groupId: meetup.groupId, tag: updatedMeetupTag)).thenDoNothing()
            when(stub.loadMeetup(meetup.groupId)).thenReturn(meetup)
            when(stub.isMember(userId: signedInUser.userId, groupId: meetup.groupId)).thenReturn(true)
        }

        firstly {
            meetupManager.join(meetup)
        }.done {
            let membershipCheck = Membership(userId: self.signedInUser.userId, publicSigningKey: self.signedInUser.publicSigningKey, groupId: self.meetup.groupId, admin: false, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedMembershipCertificate: serverSignedCertificate, adminSignedMembershipCertificate: nil)
            verify(self.groupStorageManager).store(membershipCheck)

            verify(self.groupStorageManager).updateMeetupTag(groupId: self.meetup.groupId, tag: updatedMeetupTag)
        }.catch { error in
            XCTFail(String(describing: error))
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testLeaveMeetup() {
        let completion = expectation(description: "Completion")

        let updatedMeetupTag = "updatedMeetupTag"

        stub(groupManager) { stub in
            when(stub.leave(any())).thenReturn(Promise.value(updatedMeetupTag))
        }

        stub(groupStorageManager) { stub in
            when(stub.removeMembership(userId: signedInUser.userId, groupId: meetup.groupId, updatedGroupTag: updatedMeetupTag)).thenDoNothing()
            when(stub.loadMeetup(meetup.groupId)).thenReturn(meetup)
            when(stub.isMember(userId: signedInUser.userId, groupId: meetup.groupId)).thenReturn(false)
        }

        firstly {
            meetupManager.leave(meetup)
        }.done {
            verify(self.groupStorageManager).removeMembership(userId: self.signedInUser.userId, groupId: self.meetup.groupId, updatedGroupTag: updatedMeetupTag)
        }.catch { error in
            XCTFail(String(describing: error))
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testDeleteMeetup() {
        let completion = expectation(description: "Completion")

        let selfSignedCertificate = "selfSignedCertificate"
        let serverSignedCertificate = "serverSignedCertificate"
        let teamMembership = Membership(userId: signedInUser.userId, publicSigningKey: signedInUser.publicSigningKey, groupId: meetup.teamId, admin: false, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedMembershipCertificate: serverSignedCertificate, adminSignedMembershipCertificate: nil)
        let meetupMembership = Membership(userId: signedInUser.userId, publicSigningKey: signedInUser.publicSigningKey, groupId: meetup.groupId, admin: true, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedMembershipCertificate: serverSignedCertificate, adminSignedMembershipCertificate: nil)
        let otherMembership = Membership(userId: UserId(), publicSigningKey: Data(), groupId: meetup.groupId, admin: false, selfSignedMembershipCertificate: nil, serverSignedMembershipCertificate: serverSignedCertificate, adminSignedMembershipCertificate: nil)

        stub(groupStorageManager) { stub in
            when(stub.loadMembership(userId: signedInUser.userId, groupId: meetup.teamId)).thenReturn(teamMembership)
            when(stub.loadMembership(userId: signedInUser.userId, groupId: meetup.groupId)).thenReturn(meetupMembership)
            when(stub.loadMemberships(groupId: meetup.groupId)).thenReturn([meetupMembership, otherMembership])
            when(stub.teamOf(meetup: any())).thenReturn(team)
            when(stub.removeMeetup(meetup: any())).thenDoNothing()
        }

        let notificationRecipient = NotificationRecipient(userId: otherMembership.userId, serverSignedMembershipCertificate: otherMembership.serverSignedMembershipCertificate, priority: .alert)
        stub(backend) { stub in
            when(stub.deleteGroup(groupId: meetup.groupId, serverSignedAdminCertificate: serverSignedCertificate, groupTag: meetup.tag, notificationRecipients: [notificationRecipient])).thenReturn(Promise())
        }

        stub(groupManager) { stub in
            when(stub.sendGroupUpdateNotification(to: any(), action: GroupUpdate.Action.childGroupDeleted)).thenReturn(Promise())
        }

        firstly {
            meetupManager.delete(meetup)
        }.done {
            let meetupArgumentCaptor = ArgumentCaptor<Meetup>()
            verify(self.groupStorageManager).removeMeetup(meetup: meetupArgumentCaptor.capture())
            guard let removedMeetup = meetupArgumentCaptor.value else {
                XCTFail("Invalid meetup stored")
                return
            }
            XCTAssertEqual(removedMeetup.groupId, self.meetup.groupId, "Invalid meetup")

            let teamArgumentCaptor = ArgumentCaptor<Group>()
            verify(self.groupManager).sendGroupUpdateNotification(to: teamArgumentCaptor.capture(), action: GroupUpdate.Action.childGroupDeleted)
            guard let team = teamArgumentCaptor.value else {
                XCTFail("Invalid group")
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

    func testDeleteMeetupNotAdmin() {
        let completion = expectation(description: "Completion")

        let selfSignedCertificate = "selfSignedCertificate"
        let serverSignedCertificate = "serverSignedCertificate"
        let teamMembership = Membership(userId: signedInUser.userId, publicSigningKey: signedInUser.publicSigningKey, groupId: meetup.teamId, admin: false, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedMembershipCertificate: serverSignedCertificate, adminSignedMembershipCertificate: nil)
        let meetupMembership = Membership(userId: signedInUser.userId, publicSigningKey: signedInUser.publicSigningKey, groupId: meetup.groupId, admin: false, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedMembershipCertificate: serverSignedCertificate, adminSignedMembershipCertificate: nil)

        stub(groupStorageManager) { stub in
            when(stub.teamOf(meetup: meetup)).thenReturn(team)
            when(stub.loadMembership(userId: signedInUser.userId, groupId: meetup.teamId)).thenReturn(teamMembership)
            when(stub.loadMembership(userId: signedInUser.userId, groupId: meetup.groupId)).thenReturn(meetupMembership)
            when(stub.loadMemberships(groupId: meetup.groupId)).thenReturn([meetupMembership])
        }

        firstly {
            meetupManager.delete(meetup)
        }.done {
            XCTFail("Deleting meetup should not have been succeeded")
        }.catch { error in
            guard case MeetupManagerError.permissionDenied = error else {
                XCTFail(String(describing: error))
                return
            }
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }
    
    func testDeleteMeetupAsTeamAdmin() {
        let completion = expectation(description: "Completion")

        let selfSignedCertificate = "selfSignedCertificate"
        let serverSignedCertificate = "serverSignedCertificate"
        let teamMembership = Membership(userId: signedInUser.userId, publicSigningKey: signedInUser.publicSigningKey, groupId: meetup.teamId, admin: true, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedMembershipCertificate: serverSignedCertificate, adminSignedMembershipCertificate: nil)
        let meetupMembership = Membership(userId: signedInUser.userId, publicSigningKey: signedInUser.publicSigningKey, groupId: meetup.groupId, admin: false, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedMembershipCertificate: serverSignedCertificate, adminSignedMembershipCertificate: nil)

        stub(groupStorageManager) { stub in
            when(stub.loadMembership(userId: signedInUser.userId, groupId: meetup.teamId)).thenReturn(teamMembership)
            when(stub.loadMembership(userId: signedInUser.userId, groupId: meetup.groupId)).thenReturn(meetupMembership)
            when(stub.loadMemberships(groupId: meetup.groupId)).thenReturn([meetupMembership])
            when(stub.teamOf(meetup: any())).thenReturn(team)
            when(stub.removeMeetup(meetup: any())).thenDoNothing()
        }
        stub(backend) { stub in
            when(stub.deleteGroup(groupId: meetup.groupId, serverSignedAdminCertificate: serverSignedCertificate, groupTag: meetup.tag, notificationRecipients: [])).thenReturn(Promise())
        }
        stub(groupManager) { stub in
            when(stub.sendGroupUpdateNotification(to: any(), action: GroupUpdate.Action.childGroupDeleted)).thenReturn(Promise())
        }

        firstly {
            meetupManager.delete(meetup)
        }.catch { error in
            XCTFail(String(describing: error))
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testDeleteGroupMember() {
        let completion = expectation(description: "Completion")

        let selfSignedCertificate = "selfSignedCertificate"
        let serverSignedCertificate = "serverSignedCertificate"
        let membership = Membership(userId: signedInUser.userId, publicSigningKey: signedInUser.publicSigningKey, groupId: meetup.groupId, admin: true, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedMembershipCertificate: serverSignedCertificate, adminSignedMembershipCertificate: nil)

        stub(groupStorageManager) { stub in
            when(stub.loadMembership(userId: signedInUser.userId, groupId: any())).thenReturn(membership)
        }

        stub(groupManager) { stub in
            when(stub.deleteGroupMember(membership, from: any(), serverSignedMembershipCertificate: serverSignedCertificate)).thenReturn(Promise())
        }

        firstly {
            meetupManager.deleteGroupMember(membership, from: meetup)
        }.done {
            verify(self.groupManager).deleteGroupMember(membership, from: any(), serverSignedMembershipCertificate: serverSignedCertificate)
        }.catch { error in
            XCTFail(String(describing: error))
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testSetMeetingPoint() throws {
        let completion = expectation(description: "Completion")

        let selfSignedCertificate = "selfSignedCertificate"
        let serverSignedCertificate = "serverSignedCertificate"
        let membership = Membership(userId: signedInUser.userId, publicSigningKey: signedInUser.publicSigningKey, groupId: meetup.groupId, admin: true, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedMembershipCertificate: serverSignedCertificate, adminSignedMembershipCertificate: nil)

        let meetingPoint = CLLocation(latitude: 52.0, longitude: 13.0)
        let updatedMeetupTag = "updatedMeetupTag"
        stub(groupStorageManager) { stub in
            when(stub.loadMembership(userId: signedInUser.userId, groupId: meetup.groupId)).thenReturn(membership)
            when(stub.updateMeetingPoint(groupId: meetup.groupId, meetingPoint: meetingPoint.location, tag: updatedMeetupTag)).thenDoNothing()
            when(stub.loadMeetup(meetup.groupId)).thenReturn(meetup)
            when(stub.isMember(userId: signedInUser.userId, groupId: meetup.groupId)).thenReturn(true)
        }

        let encryptedInternalSettings = "encryptedInternalSettings".data

        stub(cryptoManager) { stub in
            when(stub.encrypt(any(), secretKey: meetup.groupKey)).thenReturn(encryptedInternalSettings)
        }

        let notificationRecipient = NotificationRecipient(userId: UserId(), serverSignedMembershipCertificate: "serverSignedCertificate", priority: .alert)
        stub(groupManager) { stub in
//            when(stub.deleteGroupMember(membership, from: any(), serverSignedMembershipCertificate: serverSignedCertificate)).thenReturn(Promise())
            when(stub.notificationRecipients(groupId: meetup.groupId, alert: true)).thenReturn([notificationRecipient])
        }

        let updatedEtagResponse = UpdatedEtagResponse(groupTag: updatedMeetupTag)
        stub(backend) { stub in
            when(stub.updateInternalSettings(groupId: meetup.groupId, encryptedInternalSettings: encryptedInternalSettings, serverSignedMembershipCertificate: serverSignedCertificate, groupTag: meetup.tag, notificationRecipients: [notificationRecipient])).thenReturn(Promise.value(updatedEtagResponse))
        }

        firstly {
            meetupManager.set(meetingPoint: meetingPoint.coordinate, in: meetup)
        }.done {
            verify(self.groupStorageManager).updateMeetingPoint(groupId: self.meetup.groupId, meetingPoint: meetingPoint.location, tag: updatedMeetupTag)
        }.catch { error in
            XCTFail(String(describing: error))
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testSendLocationUpdate() {
        let completion = expectation(description: "Completion")

        let location = Location(latitude: 52.0, longitude: 13.0)
        let payloadContainer = PayloadContainer(payloadType: .locationUpdateV1, payload: LocationUpdate(location: location))
        stub(groupManager) { stub in
            when(stub.send(payloadContainer: payloadContainer, to: any(), collapseId: any(Envelope.CollapseIdentifier.self), priority: MessagePriority.deferred)).thenReturn(Promise())
        }

        stub(groupStorageManager) { stub in
            when(stub.loadMeetups()).thenReturn([meetup])
            when(stub.isMember(userId: signedInUser.userId, groupId: meetup.groupId)).thenReturn(true)
        }

        firstly {
            meetupManager.sendLocationUpdate(location: location)
        }.done {
            let meetupArgumentCaptor = ArgumentCaptor<Group>()
            verify(self.groupManager).send(payloadContainer: payloadContainer, to: meetupArgumentCaptor.capture(), collapseId: any(), priority: MessagePriority.deferred)
            guard let meetup = meetupArgumentCaptor.value else {
                XCTFail("Invalid group")
                return
            }
            XCTAssertEqual(meetup.groupId, self.meetup.groupId, "Invalid meetup")
        }.catch { error in
            XCTFail(String(describing: error))
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testProcessLocationUpdate() {
        let completion = expectation(description: "Completion")

        let location = Location(latitude: 52.0, longitude: 13.0)
        let payloadContainer = PayloadContainer(payloadType: .locationUpdateV1, payload: LocationUpdate(location: location))
        stub(groupManager) { stub in
            when(stub.send(payloadContainer: payloadContainer, to: any(), collapseId: any(Envelope.CollapseIdentifier.self), priority: MessagePriority.deferred)).then { _, _, _, _ in
                completion.fulfill()
                return Promise()
            }
        }

        stub(groupStorageManager) { stub in
            when(stub.isMember(userId: signedInUser.userId, groupId: meetup.groupId)).thenReturn(true)
            when(stub.loadMeetups()).thenReturn([meetup])
        }

        meetupManager.processLocationUpdate(location: location)

        wait(for: [completion])

        let meetupArgumentCaptor = ArgumentCaptor<Group>()
        verify(self.groupManager).send(payloadContainer: payloadContainer, to: meetupArgumentCaptor.capture(), collapseId: any(), priority: MessagePriority.deferred)
        guard let meetup = meetupArgumentCaptor.value else {
            XCTFail("Invalid group")
            return
        }
        XCTAssertEqual(meetup.groupId, self.meetup.groupId, "Invalid meetup")
    }
}
