//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import XCTest
import GRDB
import TICEAPIModels

@testable import TICE

class GroupStorageManagerTests: XCTestCase {
    var database: DatabaseWriter!
    
    var groupStorageManager: GroupStorageManager!
    
    override func setUpWithError() throws {
        database = DatabaseQueue()
        groupStorageManager = GroupStorageManager(database: database)
        
        try database.write { db in
            try db.create(table: User.databaseTableName, ifNotExists: true) { t in
                t.column("userId", .blob).primaryKey()
                t.column("publicSigningKey", .blob).notNull()
                t.column("publicName", .text)
            }
            
            try db.create(table: Team.databaseTableName, ifNotExists: true) { t in
                t.column("groupId", .blob).primaryKey()
                t.column("groupKey", .blob).notNull()
                t.column("owner", .blob).notNull()
                t.column("joinMode", .integer).notNull()
                t.column("permissionMode", .integer).notNull()
                t.column("url", .blob).notNull()
                t.column("tag", .text).notNull()
                t.column("name", .text)
                t.column("meetupId", .blob)
                t.column("meetingPoint", .blob)
            }

            if try !db.tableExists(Meetup.databaseTableName) {
                try db.create(table: Meetup.databaseTableName, ifNotExists: true) { t in
                    t.column("groupId", .blob).primaryKey()
                    t.column("groupKey", .blob).notNull()
                    t.column("owner", .blob).notNull()
                    t.column("joinMode", .integer).notNull()
                    t.column("permissionMode", .integer).notNull()
                    t.column("tag", .text).notNull()
                    t.column("teamId", .blob)
                        .notNull()
                        .indexed()
                        .references(Team.databaseTableName, column: "groupId", onDelete: .cascade)
                    t.column("meetingPoint", .blob)
                    t.column("locationSharingEnabled", .boolean)
                }
            }

            try db.create(table: Membership.databaseTableName, ifNotExists: true) { t in
                t.column("userId", .blob)
                    .notNull()
                    .references(User.databaseTableName, onDelete: .cascade)
                t.column("groupId", .blob)
                    .notNull()
                t.column("publicSigningKey", .blob).notNull()
                t.column("admin", .boolean).notNull()
                t.column("selfSignedMembershipCertificate", .text)
                t.column("serverSignedMembershipCertificate", .text).notNull()
                t.column("adminSignedMembershipCertificate", .text)

                t.primaryKey(["userId", "groupId"])
            }
        }
    }
    
    func testStoreTeam() throws {
        var team = Team(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "https://example.com")!, name: nil, meetupId: nil)
        
        try groupStorageManager.storeTeam(team)
        
        XCTAssertEqual(try database.read { try Team.fetchOne($0)! }, team)
        
        let meetup = Meetup(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", teamId: team.groupId, meetingPoint: nil, locationSharingEnabled: false)
        team.meetupId = meetup.groupId
        
        try database.write { db in
            try team.save(db)
            try meetup.save(db)
        }
        
        team.meetupId = nil
        try groupStorageManager.storeTeam(team)
        
        XCTAssertNil(try database.read { try Team.fetchOne($0)! }.meetupId)
        XCTAssertEqual(try database.read { try Meetup.fetchCount($0) }, 0)
    }
    
    func testLoadTeams() throws {
        let team1 = Team(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "https://example.com")!, name: nil, meetupId: nil)
        let team2 = Team(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "https://example.com")!, name: nil, meetupId: nil)
        
        try database.write { db in
            try team1.save(db)
            try team2.save(db)
        }
        
        XCTAssertEqual(try groupStorageManager.loadTeams(), [team1, team2])
        XCTAssertEqual(try groupStorageManager.loadTeam(team1.groupId), team1)
    }
    
    func testUpdateTeamTag() throws {
        var team = Team(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "https://example.com")!, name: nil, meetupId: nil)
        
        try database.write { db in
            try team.save(db)
        }
        
        team.tag = "newTag"
        try groupStorageManager.updateTeamTag(groupId: team.groupId, tag: team.tag)
        XCTAssertEqual(try database.read { try Team.fetchOne($0)! }.tag, team.tag)
    }
    
    func testUpdateTeamName() throws {
        var team = Team(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "https://example.com")!, name: nil, meetupId: nil)
        
        try database.write { db in
            try team.save(db)
        }
        
        team.tag = "newTag"
        team.name = "newName"
        try groupStorageManager.updateTeamName(groupId: team.groupId, name: team.name, tag: team.tag)
        XCTAssertEqual(try database.read { try Team.fetchOne($0)! }.tag, team.tag)
        XCTAssertEqual(try database.read { try Team.fetchOne($0)! }.name, team.name)
    }
    
    func testRemoveTeam() throws {
        let team = Team(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "https://example.com")!, name: nil, meetupId: nil)
        let user = User(userId: UserId(), publicSigningKey: PublicKey(), publicName: nil)
        let membership = Membership(userId: user.userId, publicSigningKey: user.publicSigningKey, groupId: team.groupId, admin: true, serverSignedMembershipCertificate: "")
        
        try database.write { db in
            try team.save(db)
            try user.save(db)
            try membership.save(db)
        }
        
        try groupStorageManager.removeTeam(team.groupId)
        XCTAssertEqual(try database.read { try Team.fetchCount($0) }, 0)
        XCTAssertEqual(try database.read { try Membership.fetchCount($0) }, 0)
    }
    
    func testMeetupInTeam() throws {
        var team = Team(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "https://example.com")!, name: nil, meetupId: nil)
        let meetup = Meetup(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", teamId: team.groupId, meetingPoint: nil, locationSharingEnabled: false)
        team.meetupId = meetup.groupId
        
        try database.write { db in
            try team.save(db)
            try meetup.save(db)
        }
        
        XCTAssertEqual(try groupStorageManager.meetupIn(team: team)?.groupId, meetup.groupId)
    }
    
    func testObserveTeams() throws {
        var teams: [Team] = []
        let observationCallbackLock = DispatchSemaphore(value: 0)
        let observerToken = groupStorageManager.observeTeams(queue: .global()) {
            teams = $0
            observationCallbackLock.signal()
        }
        
        observationCallbackLock.wait()
        
        XCTAssertTrue(teams.isEmpty)
        
        let team = Team(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "https://example.com")!, name: nil, meetupId: nil)
        try database.write { try team.save($0) }
        
        observationCallbackLock.wait()
        
        XCTAssertEqual(teams, [team])
        
        observerToken.cancel()
    }
    
    func testObserveTeam() throws {
        var team = Team(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "https://example.com")!, name: nil, meetupId: nil)
        try database.write { try team.save($0) }
        
        var observedTeam: Team?
        var observedMembers: [Member] = []
        let observationCallbackLock = DispatchSemaphore(value: 0)
        let observerToken = groupStorageManager.observeTeam(groupId: team.groupId, queue: .global()) { team, members in
            observedTeam = team
            observedMembers = members
            observationCallbackLock.signal()
        }
        
        observationCallbackLock.wait()
        XCTAssertEqual(observedTeam, team)
        
        team.tag = "newTag"
        try database.write { try team.save($0) }
        
        observationCallbackLock.wait()
        XCTAssertEqual(observedTeam?.tag, team.tag)
        
        let user = User(userId: UserId(), publicSigningKey: PublicKey(), publicName: nil)
        let membership = Membership(userId: user.userId, publicSigningKey: user.publicSigningKey, groupId: team.groupId, admin: true, serverSignedMembershipCertificate: "")
        let member = Member(membership: membership, user: user)
        try database.write { db in
            try user.save(db)
            try membership.save(db)
        }
        
        observationCallbackLock.wait()
        XCTAssertEqual(observedMembers.count, 1)
        XCTAssertEqual(observedMembers.first!.membership, member.membership)
        
        observerToken.cancel()
    }
    
    func testStoreMeetup() throws {
        let team = Team(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "https://example.com")!, name: nil, meetupId: nil)
        let meetup = Meetup(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", teamId: team.groupId, meetingPoint: nil, locationSharingEnabled: false)
        
        XCTAssertThrowsError(try groupStorageManager.storeMeetup(meetup)) { error in
            guard case GroupStorageManagerError.groupNotFound = error else {
                XCTFail("Meetup without Team should not have been stored.")
                return
            }
        }
        
        try database.write { try team.save($0) }
        
        try groupStorageManager.storeMeetup(meetup)
        
        XCTAssertEqual(try database.read { try Meetup.fetchOne($0)! }.groupId, meetup.groupId)
        XCTAssertEqual(try database.read { try Team.fetchOne($0)! }.meetupId, meetup.groupId)
    }
    
    func testLoadMeetups() throws {
        let team1 = Team(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "https://example.com")!, name: nil, meetupId: nil)
        let meetup1 = Meetup(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", teamId: team1.groupId, meetingPoint: nil, locationSharingEnabled: false)
        
        let team2 = Team(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "https://example.com")!, name: nil, meetupId: nil)
        let meetup2 = Meetup(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", teamId: team2.groupId, meetingPoint: nil, locationSharingEnabled: false)
        
        try database.write { db in
            try team1.save(db)
            try team2.save(db)
            try meetup1.save(db)
            try meetup2.save(db)
        }
        
        XCTAssertEqual(try groupStorageManager.loadMeetups().map(\.groupId), [meetup1, meetup2].map(\.groupId))
        XCTAssertEqual(try groupStorageManager.loadMeetup(meetup1.groupId)?.groupId, meetup1.groupId)
    }
    
    func testUpdateMeetupTag() throws {
        let team = Team(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "https://example.com")!, name: nil, meetupId: nil)
        var meetup = Meetup(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", teamId: team.groupId, meetingPoint: nil, locationSharingEnabled: false)
        
        try database.write { db in
            try team.save(db)
            try meetup.save(db)
        }
        
        meetup.tag = "newTag"
        try groupStorageManager.updateMeetupTag(groupId: meetup.groupId, tag: meetup.tag)
        XCTAssertEqual(try database.read { try Meetup.fetchOne($0)! }.tag, meetup.tag)
    }
    
    func testUpdateMeetingPoint() throws {
        var team = Team(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "https://example.com")!, name: nil, meetupId: nil)
        
        try database.write { db in
            try team.save(db)
        }
        
        team.meetingPoint = Location(latitude: 52.0, longitude: 13.0)
        team.tag = "newTag"
        try groupStorageManager.updateMeetingPoint(groupId: team.groupId, meetingPoint: team.meetingPoint, tag: team.tag)
        XCTAssertEqual(try database.read { try Team.fetchOne($0)! }.meetingPoint?.coordinate, team.meetingPoint?.coordinate)
        XCTAssertEqual(try database.read { try Team.fetchOne($0)! }.tag, team.tag)
    }
    
//    func testUpdateLocationSharing() throws {
//        let team = Team(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "https://example.com")!, name: nil, meetupId: nil)
//        let meetup = Meetup(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", teamId: team.groupId, meetingPoint: nil, locationSharingEnabled: false)
//        
//        try database.write { db in
//            try team.save(db)
//            try meetup.save(db)
//        }
//        
//        try groupStorageManager.updateLocationSharing(meetupId: meetup.groupId, enabled: true)
//        XCTAssertTrue(try database.read { try Meetup.fetchOne($0)! }.locationSharingEnabled)
//    }
    
    func testRemoveMeetup() throws {
        var team = Team(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "https://example.com")!, name: nil, meetupId: nil)
        let meetup = Meetup(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", teamId: team.groupId, meetingPoint: nil, locationSharingEnabled: false)
        team.meetupId = meetup.groupId
        let user = User(userId: UserId(), publicSigningKey: PublicKey(), publicName: nil)
        let membership = Membership(userId: user.userId, publicSigningKey: user.publicSigningKey, groupId: meetup.groupId, admin: true, serverSignedMembershipCertificate: "")
        
        try database.write { db in
            try team.save(db)
            try meetup.save(db)
            try user.save(db)
            try membership.save(db)
        }
        
        try groupStorageManager.removeMeetup(meetup: meetup)
        XCTAssertEqual(try database.read { try Meetup.fetchCount($0) }, 0)
        XCTAssertNil(try database.read { try Team.fetchOne($0)! }.meetupId)
        XCTAssertEqual(try database.read { try Membership.fetchCount($0) }, 0)
    }
    
    func testTeamOfMeetup() throws {
        var team = Team(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "https://example.com")!, name: nil, meetupId: nil)
        let meetup = Meetup(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", teamId: team.groupId, meetingPoint: nil, locationSharingEnabled: false)
        team.meetupId = meetup.groupId
        
        try database.write { db in
            try team.save(db)
            try meetup.save(db)
        }
        
        XCTAssertEqual(try groupStorageManager.teamOf(meetup: meetup), team)
    }
    
    func testObserveMeetups() throws {
        var meetups: [Meetup] = []
        let observationCallbackLock = DispatchSemaphore(value: 0)
        let observerToken = groupStorageManager.observeMeetups(queue: .global()) {
            meetups = $0
            observationCallbackLock.signal()
        }
        
        observationCallbackLock.wait()
        
        XCTAssertTrue(meetups.isEmpty)
        
        var team = Team(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "https://example.com")!, name: nil, meetupId: nil)
        let meetup = Meetup(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", teamId: team.groupId, meetingPoint: nil, locationSharingEnabled: false)
        team.meetupId = meetup.groupId
        
        try database.write { db in
            try team.save(db)
            try meetup.save(db)
        }
        
        observationCallbackLock.wait()
        
        XCTAssertEqual(meetups.count, 1)
        XCTAssertEqual(meetups.first!.groupId, meetup.groupId)
        
        observerToken.cancel()
    }
    
    func testObserveMeetup() throws {
        var team = Team(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "https://example.com")!, name: nil, meetupId: nil)
        var meetup = Meetup(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", teamId: team.groupId, meetingPoint: nil, locationSharingEnabled: false)
        team.meetupId = meetup.groupId
        
        try database.write { db in
            try team.save(db)
            try meetup.save(db)
        }
        
        var observedMeetup: Meetup?
        var observedMembers: [Member] = []
        let observationCallbackLock = DispatchSemaphore(value: 0)
        let observerToken = groupStorageManager.observeMeetup(groupId: meetup.groupId, queue: .global()) { meetup, members in
            observedMeetup = meetup
            observedMembers = members
            observationCallbackLock.signal()
        }
        
        observationCallbackLock.wait()
        XCTAssertEqual(observedMeetup?.groupId, meetup.groupId)
        
        meetup.tag = "newTag"
        try database.write { try meetup.save($0) }
        
        observationCallbackLock.wait()
        XCTAssertEqual(observedMeetup?.tag, meetup.tag)
        
        let user = User(userId: UserId(), publicSigningKey: PublicKey(), publicName: nil)
        let membership = Membership(userId: user.userId, publicSigningKey: user.publicSigningKey, groupId: meetup.groupId, admin: true, serverSignedMembershipCertificate: "")
        let member = Member(membership: membership, user: user)
        try database.write { db in
            try user.save(db)
            try membership.save(db)
        }
        
        observationCallbackLock.wait()
        XCTAssertEqual(observedMembers.count, 1)
        XCTAssertEqual(observedMembers.first?.membership, member.membership)
        
        observerToken.cancel()
    }
    
    func testMeetupState() throws {
        var team = Team(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "https://example.com")!, name: nil, meetupId: nil)
        
        try database.write { db in
            try team.save(db)
        }
        
        let user = User(userId: UserId(), publicSigningKey: PublicKey(), publicName: nil)
        
        guard case MeetupState.none = try groupStorageManager.meetupState(teamId: team.groupId, userId: user.userId) else {
            XCTFail("Invalid meetup state")
            return
        }
        
        let meetup = Meetup(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", teamId: team.groupId, meetingPoint: nil, locationSharingEnabled: false)
        team.meetupId = meetup.groupId
        
        try database.write { db in
            try team.save(db)
            try meetup.save(db)
        }
        
        guard case MeetupState.invited(let invitedMeetup) = try groupStorageManager.meetupState(teamId: team.groupId, userId: user.userId),
              invitedMeetup.groupId == meetup.groupId else {
            XCTFail("Invalid meetup state")
            return
        }
        
        let membership = Membership(userId: user.userId, publicSigningKey: user.publicSigningKey, groupId: meetup.groupId, admin: true, serverSignedMembershipCertificate: "")
        
        try database.write { db in
            try user.save(db)
            try membership.save(db)
        }
        
        guard case MeetupState.participating(let participatingMeetup) = try groupStorageManager.meetupState(teamId: team.groupId, userId: user.userId),
              participatingMeetup.groupId == meetup.groupId else {
            XCTFail("Invalid meetup state")
            return
        }
    }
    
    func testMeetupStateObservation() throws {
        var team = Team(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "https://example.com")!, name: nil, meetupId: nil)
        
        try database.write { db in
            try team.save(db)
        }
        
        let user = User(userId: UserId(), publicSigningKey: PublicKey(), publicName: nil)
        var observedMeetupState: MeetupState?
        let observationCallbackLock = DispatchSemaphore(value: 0)
        let observationToken = groupStorageManager.observeMeetupState(teamId: team.groupId, userId: user.userId, queue: .global()) { meetupState in
            observedMeetupState = meetupState
            observationCallbackLock.signal()
        }
        
        guard observationCallbackLock.wait(timeout: .now() + 200.0) == .success else {
            XCTFail()
            return
        }
        
        guard let noneState = observedMeetupState,
              case MeetupState.none = noneState else {
            XCTFail("Invalid meetup state")
            return
        }
        
        let meetup = Meetup(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", teamId: team.groupId, meetingPoint: nil, locationSharingEnabled: false)
        team.meetupId = meetup.groupId
        
        try database.write { db in
            try team.save(db)
            try meetup.save(db)
        }
        
        guard observationCallbackLock.wait(timeout: .now() + 200.0) == .success else {
            XCTFail()
            return
        }
        
        guard let invitedState = observedMeetupState,
              case MeetupState.invited(let invitedMeetup) = invitedState,
              invitedMeetup.groupId == meetup.groupId else {
            XCTFail("Invalid meetup state")
            return
        }
        
        let membership = Membership(userId: user.userId, publicSigningKey: user.publicSigningKey, groupId: meetup.groupId, admin: true, serverSignedMembershipCertificate: "")
        
        try database.write { db in
            try user.save(db)
            try membership.save(db)
        }
        
        guard observationCallbackLock.wait(timeout: .now() + 200.0) == .success else {
            XCTFail()
            return
        }
        
        guard let participatingState = observedMeetupState,
              case MeetupState.participating(let participatingMeetup) = participatingState,
              participatingMeetup.groupId == meetup.groupId else {
            XCTFail("Invalid meetup state")
            return
        }
        
        observationToken.cancel()
    }
    
    func testStoreMembership() throws {
        let team = Team(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "https://example.com")!, name: nil, meetupId: nil)
        
        let user = User(userId: UserId(), publicSigningKey: PublicKey(), publicName: nil)
        let membership = Membership(userId: user.userId, publicSigningKey: user.publicSigningKey, groupId: team.groupId, admin: true, serverSignedMembershipCertificate: "")
        
        try database.write { try user.save($0) }
        
        try groupStorageManager.store(membership)
        
        XCTAssertEqual(try database.read { try Membership.fetchOne($0) }, membership)
    }
    
    func testStoreMemberships() throws {
        let team = Team(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "https://example.com")!, name: nil, meetupId: nil)
        
        let oldUser = User(userId: UserId(), publicSigningKey: PublicKey(), publicName: nil)
        let oldMembership = Membership(userId: oldUser.userId, publicSigningKey: oldUser.publicSigningKey, groupId: team.groupId, admin: true, serverSignedMembershipCertificate: "")
        
        let newUser = User(userId: UserId(), publicSigningKey: PublicKey(), publicName: nil)
        
        try database.write { db in
            try oldUser.save(db)
            try newUser.save(db)
            try oldMembership.save(db)
        }
        
        let newMembership = Membership(userId: newUser.userId, publicSigningKey: newUser.publicSigningKey, groupId: team.groupId, admin: true, serverSignedMembershipCertificate: "")
        
        try groupStorageManager.store([newMembership], for: team.groupId)
        
        XCTAssertEqual(try database.read { try Membership.fetchCount($0) }, 1)
        XCTAssertEqual(try database.read { try Membership.fetchOne($0) }, newMembership)
    }
    
    func testLoadMembership() throws {
        let team = Team(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "https://example.com")!, name: nil, meetupId: nil)
        
        let user1 = User(userId: UserId(), publicSigningKey: PublicKey(), publicName: nil)
        let membership1 = Membership(userId: user1.userId, publicSigningKey: user1.publicSigningKey, groupId: team.groupId, admin: true, serverSignedMembershipCertificate: "")
        
        let user2 = User(userId: UserId(), publicSigningKey: PublicKey(), publicName: nil)
        let membership2 = Membership(userId: user2.userId, publicSigningKey: user2.publicSigningKey, groupId: team.groupId, admin: true, serverSignedMembershipCertificate: "")
        
        try database.write { db in
            try user1.save(db)
            try user2.save(db)
            try membership1.save(db)
            try membership2.save(db)
        }
        
        XCTAssertEqual(try groupStorageManager.loadMemberships(groupId: team.groupId), [membership1, membership2])
        XCTAssertEqual(try groupStorageManager.loadMemberships(userId: user1.userId), [membership1])
        XCTAssertEqual(try groupStorageManager.loadMembership(userId: user1.userId, groupId: team.groupId), membership1)
    }
    
    func testRemoveMembership() throws {
        let team = Team(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "https://example.com")!, name: nil, meetupId: nil)
        
        let user = User(userId: UserId(), publicSigningKey: PublicKey(), publicName: nil)
        let membership = Membership(userId: user.userId, publicSigningKey: user.publicSigningKey, groupId: team.groupId, admin: true, serverSignedMembershipCertificate: "")
        
        try database.write { db in
            try team.save(db)
            try user.save(db)
            try membership.save(db)
        }
        
        let updatedGroupTag = "updatedGroupTag"
        try groupStorageManager.removeMembership(userId: user.userId, groupId: team.groupId, updatedGroupTag: updatedGroupTag)
        
        XCTAssertEqual(try database.read { try Membership.fetchCount($0) }, 0)
        XCTAssertEqual(try database.read { try Team.fetchOne($0) }?.tag, updatedGroupTag)
    }
    
    func testIsMember() throws {
        let team = Team(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "https://example.com")!, name: nil, meetupId: nil)
        
        let user1 = User(userId: UserId(), publicSigningKey: PublicKey(), publicName: nil)
        let user2 = User(userId: UserId(), publicSigningKey: PublicKey(), publicName: nil)
        let membership = Membership(userId: user1.userId, publicSigningKey: user1.publicSigningKey, groupId: team.groupId, admin: true, serverSignedMembershipCertificate: "")
        
        try database.write { db in
            try user1.save(db)
            try user2.save(db)
            try membership.save(db)
        }
        
        XCTAssertTrue(try groupStorageManager.isMember(userId: user1.userId, groupId: team.groupId))
        XCTAssertFalse(try groupStorageManager.isMember(userId: user2.userId, groupId: team.groupId))
    }
    
    func testUserForMembership() throws {
        let team = Team(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "https://example.com")!, name: nil, meetupId: nil)
        
        let user = User(userId: UserId(), publicSigningKey: PublicKey(), publicName: nil)
        let membership = Membership(userId: user.userId, publicSigningKey: user.publicSigningKey, groupId: team.groupId, admin: true, serverSignedMembershipCertificate: "")
        
        try database.write { db in
            try user.save(db)
            try membership.save(db)
        }
        
        XCTAssertEqual(try groupStorageManager.user(for: membership), user)
    }
    
    func testMembers() throws {
        let team = Team(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "https://example.com")!, name: nil, meetupId: nil)
        
        let user1 = User(userId: UserId(), publicSigningKey: PublicKey(), publicName: nil)
        let user2 = User(userId: UserId(), publicSigningKey: PublicKey(), publicName: nil)
        let membership = Membership(userId: user1.userId, publicSigningKey: user1.publicSigningKey, groupId: team.groupId, admin: true, serverSignedMembershipCertificate: "")
        
        try database.write { db in
            try user1.save(db)
            try user2.save(db)
            try membership.save(db)
        }
        
        let members = try groupStorageManager.members(groupId: team.groupId)
        
        XCTAssertEqual(members.count, 1)
        XCTAssertEqual(members.first!.membership, membership)
        XCTAssertEqual(members.first!.user, user1)
    }
    
    func testObserveIsMember() throws {
        let team = Team(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "https://example.com")!, name: nil, meetupId: nil)
        
        let user = User(userId: UserId(), publicSigningKey: PublicKey(), publicName: nil)
        
        var observedIsMember: Bool?
        let observationCallbackLock = DispatchSemaphore(value: 0)
        let observerToken = groupStorageManager.observeIsMember(groupId: team.groupId, userId: user.userId, queue: .global()) { isMember in
            observedIsMember = isMember
            observationCallbackLock.signal()
        }
        
        observationCallbackLock.wait()
        XCTAssertFalse(observedIsMember!)
        
        let membership = Membership(userId: user.userId, publicSigningKey: user.publicSigningKey, groupId: team.groupId, admin: true, serverSignedMembershipCertificate: "")
        
        try database.write { db in
            try user.save(db)
            try membership.save(db)
        }
        
        observationCallbackLock.wait()
        XCTAssertTrue(observedIsMember!)
        
        observerToken.cancel()
    }
    
    func testObserveMembers() throws {
        let team = Team(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "https://example.com")!, name: nil, meetupId: nil)
        let user = User(userId: UserId(), publicSigningKey: PublicKey(), publicName: nil)
        let membership = Membership(userId: user.userId, publicSigningKey: user.publicSigningKey, groupId: team.groupId, admin: true, serverSignedMembershipCertificate: "")
        
        try database.write { db in
            try user.save(db)
        }
        
        var observedMembers: [Member] = []
        let observationCallbackLock = DispatchSemaphore(value: 0)
        let observerToken = groupStorageManager.observeMembers(queue: .global()) { members in
            observedMembers = members
            observationCallbackLock.signal()
        }
        
        observationCallbackLock.wait()
        XCTAssertTrue(observedMembers.isEmpty)
        
        try database.write { db in
            try membership.save(db)
        }
        
        observationCallbackLock.wait()
        XCTAssertEqual(observedMembers.count, 1)
        XCTAssertEqual(observedMembers.first?.user.userId, user.userId)
        
        user.publicName = "publicName"
        
        try database.write { db in
            try user.save(db)
        }
        
        observationCallbackLock.wait()
        XCTAssertEqual(observedMembers.count, 1)
        XCTAssertEqual(observedMembers.first?.user.publicName, user.publicName)
        
        observerToken.cancel()
    }
    
    func testLoadGroup() throws {
        var team = Team(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "https://example.com")!, name: nil, meetupId: nil)
        let meetup = Meetup(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", teamId: team.groupId, meetingPoint: nil, locationSharingEnabled: false)
        team.meetupId = meetup.groupId
        
        try database.write { db in
            try team.save(db)
            try meetup.save(db)
        }
        
        XCTAssertEqual((try groupStorageManager.loadGroup(groupId: team.groupId) as? Team), team)
        XCTAssertEqual((try groupStorageManager.loadGroup(groupId: meetup.groupId) as? Meetup)?.groupId, meetup.groupId)
    }
    
    func testUpdateGroupTag() throws {
        var team = Team(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "https://example.com")!, name: nil, meetupId: nil)
        let meetup = Meetup(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", teamId: team.groupId, meetingPoint: nil, locationSharingEnabled: false)
        team.meetupId = meetup.groupId
        
        try database.write { db in
            try team.save(db)
            try meetup.save(db)
        }
        
        let newTeamTag = "newTeamTag"
        let newMeetupTag = "newMeetupTag"
        
        try groupStorageManager.updateGroupTag(groupId: team.groupId, tag: newTeamTag)
        try groupStorageManager.updateGroupTag(groupId: meetup.groupId, tag: newMeetupTag)
        
        XCTAssertEqual(try database.read { try Team.fetchOne($0)! }.tag, newTeamTag)
        XCTAssertEqual(try database.read { try Meetup.fetchOne($0)! }.tag, newMeetupTag)
    }
    
    func testDeleteAllData() throws {
        var team = Team(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", url: URL(string: "https://example.com")!, name: nil, meetupId: nil)
        let meetup = Meetup(groupId: GroupId(), groupKey: SecretKey(), owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "", teamId: team.groupId, meetingPoint: nil, locationSharingEnabled: false)
        team.meetupId = meetup.groupId
        
        let user = User(userId: UserId(), publicSigningKey: PublicKey(), publicName: nil)
        let membership = Membership(userId: user.userId, publicSigningKey: user.publicSigningKey, groupId: team.groupId, admin: true, serverSignedMembershipCertificate: "")
        
        try database.write { db in
            try team.save(db)
            try meetup.save(db)
            try user.save(db)
            try membership.save(db)
        }
        
        groupStorageManager.deleteAllData()
        
        XCTAssertFalse(try database.read { try $0.tableExists(Team.databaseTableName) })
        XCTAssertFalse(try database.read { try $0.tableExists(Meetup.databaseTableName) })
        XCTAssertFalse(try database.read { try $0.tableExists(Membership.databaseTableName) })
    }
}
