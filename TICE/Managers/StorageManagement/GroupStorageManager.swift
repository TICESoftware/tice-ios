//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels
import GRDB

enum GroupStorageManagerError: LocalizedError {
    case groupNotFound
    case membershipNotFound
    case userNotFound

    var errorDescription: String? {
        switch self {
        case .groupNotFound: return L10n.Error.GroupStorageManager.groupNotFound
        case .membershipNotFound: return L10n.Error.GroupStorageManager.membershipNotFound
        case .userNotFound: return L10n.Error.GroupStorageManager.userNotFound
        }
    }
}

class GroupStorageManager: GroupStorageManagerType {

    let database: DatabaseWriter

    init(database: DatabaseWriter) {
        self.database = database
    }

    // MARK: Teams

    func storeTeam(_ team: Team) throws {
        try database.write { db in
            try team.save(db)

            if team.meetupId == nil {
                try team.meetup.deleteAll(db)
            }
        }
    }

    func loadTeams() throws -> [Team] {
        try database.read { db in
            try Team.fetchAll(db)
        }
    }

    func loadTeam(_ groupId: GroupId) throws -> Team? {
        try database.read { db in
            try Team.fetchOne(db, key: groupId)
        }
    }

    func updateTeamTag(groupId: GroupId, tag: GroupTag) throws {
        try database.write { db in
            guard var team = try Team.fetchOne(db, key: groupId) else {
                throw GroupStorageManagerError.groupNotFound
            }
            try team.updateChanges(db) { $0.tag = tag }
        }
    }

    func updateTeamName(groupId: GroupId, name: String?, tag: GroupTag) throws {
        try database.write { db in
            guard var team = try Team.fetchOne(db, key: groupId) else {
                throw GroupStorageManagerError.groupNotFound
            }
            try team.updateChanges(db) {
                $0.name = name
                $0.tag = tag
            }
        }
    }

    func removeTeam(_ groupId: GroupId) throws {
        return try database.write { db in
            try Team.deleteOne(db, key: groupId)
            try Membership
                .filter(Column("groupId") == groupId)
                .deleteAll(db)
        }
    }

    func meetupIn(team: Team) throws -> Meetup? {
        try database.read { db in
            try team.meetup.fetchOne(db)
        }
    }
    
    func observeTeams(queue: DispatchQueue, onChange: @escaping ([Team]) -> Void) -> ObserverToken {
        database.observe(Team.fetchAll, queue: queue, onChange: onChange)
    }
    
    func observeTeam(groupId: GroupId, queue: DispatchQueue, onChange: @escaping (Team?, [Member]) -> Void) -> ObserverToken {
        database.observe({ db in
            let team = try Team.fetchOne(db, key: groupId)
            let members = try self.members(groupId: groupId, db: db)
            return (team, members)
        },
        queue: queue,
        onChange: onChange)
    }

    // MARK: Meetups

    func storeMeetup(_ meetup: Meetup) throws {
        try database.write { db in
            guard var team = try Team.fetchOne(db, key: meetup.teamId) else {
                throw GroupStorageManagerError.groupNotFound
            }

            try meetup.save(db)
            try team.updateChanges(db) { $0.meetupId = meetup.groupId }
        }
    }

    func loadMeetups() throws -> [Meetup] {
        try database.read { db in
            try Meetup.fetchAll(db)
        }
    }

    func loadMeetup(_ groupId: GroupId) throws -> Meetup? {
        try database.read { db in
            try Meetup.fetchOne(db, key: groupId)
        }
    }

    func updateMeetupTag(groupId: GroupId, tag: GroupTag) throws {
        try database.write { db in
            guard var meetup = try Meetup.fetchOne(db, key: groupId) else {
                throw GroupStorageManagerError.groupNotFound
            }
            try meetup.updateChanges(db) { $0.tag = tag }
        }
    }

    func updateMeetingPoint(groupId: GroupId, meetingPoint: Location?, tag: GroupTag) throws {
        try database.write { db in
            guard var team = try Team.fetchOne(db, key: groupId) else {
                throw GroupStorageManagerError.groupNotFound
            }
            try team.updateChanges(db) {
                $0.meetingPoint = meetingPoint
                $0.tag = tag
            }
        }
    }

    func removeMeetup(meetup: Meetup) throws {
        return try database.write { db in
            try meetup.delete(db)

            guard var team = try Team.fetchOne(db, key: meetup.teamId) else {
                throw GroupStorageManagerError.groupNotFound
            }

            try team.updateChanges(db) { $0.meetupId = nil }
            
            try Membership
                .filter(Column("groupId") == meetup.groupId)
                .deleteAll(db)
        }
    }

    func teamOf(meetup: Meetup) throws -> Team {
        try database.read { db in
            guard let team = try meetup.team.fetchOne(db) else {
                throw GroupStorageManagerError.groupNotFound
            }
            return team
        }
    }
    
    func observeMeetups(queue: DispatchQueue, onChange: @escaping ([Meetup]) -> Void) -> ObserverToken {
        database.observe(Meetup.fetchAll, queue: queue, onChange: onChange)
    }
    
    func observeMeetup(groupId: GroupId, queue: DispatchQueue, onChange: @escaping (Meetup?, [Member]) -> Void) -> ObserverToken {
        database.observe({ db in
            let meetup = try Meetup.fetchOne(db, key: groupId)
            let members = try self.members(groupId: groupId, db: db)
            return (meetup, members)
        },
        queue: queue,
        onChange: onChange)
    }
    
    func observeMeetupState(teamId: GroupId, userId: UserId, queue: DispatchQueue, onChange: @escaping (MeetupState) -> Void) -> ObserverToken {
        database.observe({ try self.meetupState(teamId: teamId, userId: userId, db: $0) }, queue: queue, onChange: onChange)
    }
    
    func meetupState(teamId: GroupId, userId: UserId) throws -> MeetupState {
        try database.read { try meetupState(teamId: teamId, userId: userId, db: $0) }
    }
    
    private func meetupState(teamId: GroupId, userId: UserId, db: Database) throws -> MeetupState {
        _ = try Membership.fetchOne(db) // Workaround for tracking Membership table as well
        
        if let meetupId = try Team.fetchOne(db, key: teamId)?.meetupId,
           let meetup = try Meetup.fetchOne(db, key: meetupId) {
            if try (meetup.owner == userId || Membership.fetchOne(db, key: ["userId": userId, "groupId": meetupId]) != nil) {
                return .participating(meetup)
            } else {
                return .invited(meetup)
            }
        } else {
            return .none
        }
    }

    // MARK: Memberships

    func store(_ membership: Membership) throws {
        try database.write { db in
            try membership.save(db)
        }
    }

    func store(_ memberships: [Membership], for groupId: GroupId) throws {
        try database.write { db in
            let userIds = memberships.map(\.userId)
            try Membership
                .filter(Column("groupId") == groupId && !userIds.contains(Column("userId")))
                .deleteAll(db)

            for membership in memberships {
                try membership.save(db)
            }
        }
    }

    func loadMemberships(groupId: GroupId) throws -> [Membership] {
        try database.read { db in
            try Membership
                .filter(Column("groupId") == groupId)
                .fetchAll(db)
        }
    }
    
    func loadMemberships(userId: UserId) throws -> [Membership] {
        try database.read { db in
            try Membership
                .filter(Column("userId") == userId)
                .fetchAll(db)
        }
    }

    func loadMembership(userId: UserId, groupId: GroupId) throws -> Membership {
        try database.read { db in
            guard let membership = try Membership.fetchOne(db, key: ["userId": userId, "groupId": groupId]) else {
                throw GroupStorageManagerError.membershipNotFound
            }
            return membership
        }
    }

    func removeMembership(userId: UserId, groupId: GroupId, updatedGroupTag: GroupTag) throws {
        return try database.write { db in
            try Membership.deleteOne(db, key: ["userId": userId, "groupId": groupId])
            try updateGroupTag(groupId: groupId, tag: updatedGroupTag, db: db)
        }
    }
    
    func isMember(userId: UserId, groupId: GroupId) throws -> Bool {
        try database.read { try isMember(userId: userId, groupId: groupId, db: $0) }
    }
    
    private func isMember(userId: UserId, groupId: GroupId, db: Database) throws -> Bool {
        try Membership.fetchOne(db, key: ["userId": userId, "groupId": groupId]) != nil
    }

    func user(for membership: Membership) throws -> User {
        try database.read { db in
            guard let user = try membership.user.fetchOne(db) else {
                throw GroupStorageManagerError.userNotFound
            }
            return user
        }
    }

    func members(groupId: GroupId) throws -> [Member] {
        try database.read { db in
            try members(groupId: groupId, db: db)
        }
    }
    
    private func members(groupId: GroupId, db: Database) throws -> [Member] {
        try Membership
            .filter(Column("groupId") == groupId)
            .fetchAll(db)
            .compactMap { membership in try membership.user.fetchOne(db).map { Member(membership: membership, user: $0) } }
    }
    
    func observeIsMember(groupId: GroupId, userId: UserId, queue: DispatchQueue, onChange: @escaping (Bool) -> Void) -> ObserverToken {
        database.observe({ try self.isMember(userId: userId, groupId: groupId, db: $0) }, queue: queue, onChange: onChange)
    }
    
    func observeMembers(queue: DispatchQueue, onChange: @escaping ([Member]) -> Void) -> ObserverToken {
        database.observe({ db in
            _ = try User.fetchOne(db) // Workaround for tracking User table as well
            return try Membership.fetchAll(db).compactMap { membership in try membership.user.fetchOne(db).map { Member(membership: membership, user: $0) } }
        },
        queue: queue,
        onChange: onChange)
    }
    
    // MARK: Groups
    
    func loadGroup(groupId: GroupId) throws -> Group {
        try database.read { db in
            if let team = try Team.fetchOne(db, key: groupId) {
                return team
            }
            
            if let meetup = try Meetup.fetchOne(db, key: groupId) {
                return meetup
            }
            
            throw GroupStorageManagerError.groupNotFound
        }
    }
    
    func updateGroupTag(groupId: GroupId, tag: GroupTag) throws {
        try database.write { try updateGroupTag(groupId: groupId, tag: tag, db: $0) }
    }
    
    private func updateGroupTag(groupId: GroupId, tag: GroupTag, db: Database) throws {
        if var team = try Team.fetchOne(db, key: groupId) {
            try team.updateChanges(db) { $0.tag = tag }
        } else {
            guard var meetup = try Meetup.fetchOne(db, key: groupId) else {
                throw GroupStorageManagerError.groupNotFound
            }
        
            try meetup.updateChanges(db) { $0.tag = tag }
        }
    }
}

extension GroupStorageManager: DeletableStorageManagerType {
    func deleteAllData() {
        do {
            try database.write {
                try $0.drop(table: Team.databaseTableName)
                try $0.drop(table: Meetup.databaseTableName)
                try $0.drop(table: Membership.databaseTableName)
            }
        } catch {
            logger.error("Error during deletion of all group data: \(String(describing: error))")
        }
    }
}

extension Team: PersistableRecord, FetchableRecord, TableRecord {
    static let meetup = hasOne(Meetup.self)

    var meetup: QueryInterfaceRequest<Meetup> { request(for: Team.meetup) }
}

extension Meetup: PersistableRecord, FetchableRecord, TableRecord {
    static let team = belongsTo(Team.self)
    static let memberships = hasMany(Membership.self)

    var team: QueryInterfaceRequest<Team> { request(for: Meetup.team) }
    var memberships: QueryInterfaceRequest<Membership> { request(for: Meetup.memberships) }
}

extension Membership {
    static let user = belongsTo(User.self)

    var user: QueryInterfaceRequest<User> { request(for: Membership.user) }
}
