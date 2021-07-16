//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//

import Foundation
import GRDB
import PromiseKit
import Version

class MigrationTo2_0_0_128: Migration {
    
    static var version = Version(major: 2, minor: 0, patch: 0, prerelease: "128")
    
    let userDefaults: UserDefaults
    
    required convenience init() throws {
        let appBundleId = Bundle.main.appBundleId
        let appGroupName = "group." + appBundleId
        let userDefaults = UserDefaults(suiteName: appGroupName)!
        self.init(userDefaults: userDefaults)
    }
    
    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }
    
    func migrate() -> Promise<Void> {
        firstly { () -> Promise<Void> in
            try migrateDemoState()
            return Promise()
        }
    }
    
    private func migrateDemoState() throws {
        guard let oldData = userDefaults.value(forKey: "state") as? Data else {
            logger.info("No demo state data to migrate.")
            return
        }
        
        let decoder = JSONDecoder.decoderWithFractionalSeconds
        let oldState = try decoder.decode(DemoManagerStatePre128.self, from: oldData)
        let newState = try oldState.migrateToPost128()
        
        let encoder = JSONEncoder.encoderWithFractionalSeconds
        let newData = try encoder.encode(newState)
        userDefaults.set(newData, forKey: "state")
    }
}

struct DemoManagerStatePre128: Codable {
    let step: DemoManagerStepPre128
    let team: DemoTeamPre128
    
    func migrateToPost128() throws -> DemoManagerState {
        return DemoManagerState(step: try step.migrateToPost128(), team: try team.migrateToPost128())
    }
}

enum DemoManagerStepPre128: Int, Codable {
    case inactive
    case notOpened
    case opened
    case chatOpened
    case chatClosed
    case meetupCreated
    case meetupEndedPrematurely
    case locationMarked
    case meetingPointCreated
    case userSelected
    case meetupEnded
    case teamDeleted
    
    func migrateToPost128() throws -> DemoManagerStep {
        switch self {
        case .inactive: return .inactive
        case .notOpened: return .notOpened
        case .opened: return .opened
        case .chatOpened: return .chatOpened
        case .chatClosed: return .chatClosed
        case .meetupCreated: return .locationSharingStarted
        case .meetupEndedPrematurely: return .locationSharingEndedPrematurely
        case .locationMarked: return .locationMarked
        case .meetingPointCreated: return .meetingPointCreated
        case .userSelected: return .userSelected
        case .meetupEnded: return .locationSharingEnded
        case .teamDeleted: return .teamDeleted
        }
    }
}

public struct DemoUserPre128: Codable, Equatable {
    var userId: UserId
    var name: String
    var role: String
    var location: Coordinate?
    
    func migrateToPost128(startedLocationSharing: Date?) throws -> DemoUser {
        return DemoUser(userId: userId, name: name, role: role, startedLocationSharing: startedLocationSharing, location: location)
    }
}

struct DemoTeamPre128: Codable {
    var groupId: GroupId
    var name: String
    var userOne: DemoUserPre128
    var userTwo: DemoUserPre128
    var meetup: DemoMeetupPre128?
    
    var members: [DemoUserPre128] { [userOne, userTwo] }
    
    func migrateToPost128() throws -> DemoTeam {
        return try DemoTeam(groupId: groupId,
                            name: name,
                            userOne: userOne.migrateToPost128(startedLocationSharing: meetup?.timestamp),
                            userTwo: userTwo.migrateToPost128(startedLocationSharing: meetup?.timestamp),
                            userSharingLocation: meetup != nil,
                            demoUsersSharingLocation: false,
                            location: meetup?.location,
                            meetingPoint: meetup?.meetingPoint)
    }
}

struct DemoMeetupPre128: Codable {
    let groupId: GroupId
    
    let location: Coordinate
    let timestamp: Date
    
    var meetingPoint: Coordinate?
}
