//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels

protocol GroupStorageManagerType: DeletableStorageManagerType {
    func loadGroup(groupId: GroupId) throws -> Group
    
    func storeTeam(_ team: Team) throws
    func storeMeetup(_ meetup: Meetup) throws

    func loadTeams() throws -> [Team]
    func loadMeetups() throws -> [Meetup]

    func loadTeam(_ groupId: GroupId) throws -> Team?
    func loadMeetup(_ groupId: GroupId) throws -> Meetup?

    func removeTeam(_ groupId: GroupId) throws
    func removeMeetup(meetup: Meetup) throws

    func meetupIn(team: Team) throws -> Meetup?
    func teamOf(meetup: Meetup) throws -> Team

    func updateTeamTag(groupId: GroupId, tag: GroupTag) throws
    func updateTeamName(groupId: GroupId, name: String?, tag: GroupTag) throws
    func updateMeetupTag(groupId: GroupId, tag: GroupTag) throws
    func updateMeetingPoint(groupId: GroupId, meetingPoint: Location?, tag: GroupTag) throws
    
    func meetupState(teamId: GroupId, userId: UserId) throws -> MeetupState
    
    func observeTeams(queue: DispatchQueue, onChange: @escaping ([Team]) -> Void) -> ObserverToken
    func observeTeam(groupId: GroupId, queue: DispatchQueue, onChange: @escaping (Team?, [Member]) -> Void) -> ObserverToken
    func observeMeetups(queue: DispatchQueue, onChange: @escaping ([Meetup]) -> Void) -> ObserverToken
    func observeMeetup(groupId: GroupId, queue: DispatchQueue, onChange: @escaping (Meetup?, [Member]) -> Void) -> ObserverToken
    func observeMeetupState(teamId: GroupId, userId: UserId, queue: DispatchQueue, onChange: @escaping (MeetupState) -> Void) -> ObserverToken

    func store(_ membership: Membership) throws
    func store(_ memberships: [Membership], for groupId: GroupId) throws
    func loadMemberships(groupId: GroupId) throws -> [Membership]
    func loadMemberships(userId: UserId) throws -> [Membership]
    func loadMembership(userId: UserId, groupId: GroupId) throws -> Membership
    func removeMembership(userId: UserId, groupId: GroupId, updatedGroupTag: GroupTag) throws
    func isMember(userId: UserId, groupId: GroupId) throws -> Bool

    func user(for membership: Membership) throws -> User
    func members(groupId: GroupId) throws -> [Member]
    
    func observeIsMember(groupId: GroupId, userId: UserId, queue: DispatchQueue, onChange: @escaping (Bool) -> Void) -> ObserverToken
    func observeMembers(queue: DispatchQueue, onChange: @escaping ([Member]) -> Void) -> ObserverToken
    
    func updateGroupTag(groupId: GroupId, tag: GroupTag) throws
}
