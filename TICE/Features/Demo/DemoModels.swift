//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels
import CoreLocation

public struct DemoUser: Codable, Equatable {
    var userId: UserId
    var name: String
    var role: String
    var startedLocationSharing: Date?
    var location: Coordinate?
    
    public static func == (lhs: DemoUser, rhs: DemoUser) -> Bool {
        lhs.userId == rhs.userId
    }
}

struct DemoTeam: Codable {
    var groupId: GroupId
    var name: String
    var userOne: DemoUser
    var userTwo: DemoUser
    var userSharingLocation: Bool
    var demoUsersSharingLocation: Bool
    var location: Coordinate?
    var meetingPoint: Coordinate?
    
    var members: [DemoUser] { [userOne] }
}

struct DemoManagerState: Codable {
    var step: DemoManagerStep
    var team: DemoTeam
    
    static var initial: DemoManagerState {
        let userOne = DemoUser(userId: UserId(uuidString: "00000000-0000-0000-0001-000000000001")!, name: L10n.Demo.Team.Member.One.name, role: L10n.Demo.Team.Member.One.description)
        let userTwo = DemoUser(userId: UserId(uuidString: "00000000-0000-0000-0001-000000000002")!, name: L10n.Demo.Team.Member.Two.name, role: L10n.Demo.Team.Member.Two.description)
        let team = DemoTeam(groupId: GroupId(uuidString: "00000000-0000-0000-0000-000000000001")!,
                            name: L10n.Demo.Team.name,
                            userOne: userOne,
                            userTwo: userTwo,
                            userSharingLocation: false,
                            demoUsersSharingLocation: false)
        return DemoManagerState(step: .inactive, team: team)
    }
}

enum DemoManagerStep: Int, Codable, CaseIterable, Comparable {
    case inactive
    case notOpened
    case opened
    case chatOpened
    case chatClosed
    case locationSharingStarted
    case locationSharingEndedPrematurely
    case locationMarked
    case meetingPointCreated
    case userSelected
    case locationSharingEnded
    case teamDeleted
    
    static func < (lhs: DemoManagerStep, rhs: DemoManagerStep) -> Bool { lhs.rawValue < rhs.rawValue }
}

extension DemoManagerStep: CustomStringConvertible {
    var description: String {
        switch self {
        case .inactive: return "Inactive"
        case .notOpened: return "NotOpened"
        case .opened: return "Opened"
        case .chatOpened: return "ChatOpened"
        case .chatClosed: return "ChatClosed"
        case .locationSharingStarted: return "LocationSharingStarted"
        case .locationSharingEndedPrematurely: return "LocationSharingEndedPrematurely"
        case .locationMarked: return "LocationMarked"
        case .meetingPointCreated: return "MeetingPointCreated"
        case .userSelected: return "UserSelected"
        case .locationSharingEnded: return "LocationSharingEnded"
        case .teamDeleted: return "TeamDeleted"
        }
    }
}
