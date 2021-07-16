//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation

enum AppState: Equatable {
    case register
    case main(MainState)
    
    enum MainState: Equatable {
        case settings
        case groups
        case createTeam
        case join(team: Team)
        case team(team: GroupId)
        case chat(team: GroupId)
        case teamSettings(team: GroupId)
        case changeName(team: GroupId)
        case createMeetupInNewGroup
        case createMeetup(team: GroupId)
        case meetupSettings(team: GroupId, meetup: GroupId)
        case demo
        case unknown
        
        var trackingName: String {
            switch self {
            case .settings: return "SETTINGS"
            case .groups: return "GROUPS"
            case .createTeam: return "CREATETEAM"
            case .join: return "JOIN"
            case .team: return "TEAM"
            case .teamSettings: return "TEAMSETTINGS"
            case .changeName: return "CHANGETEAMNAME"
            case .createMeetupInNewGroup: return "CREATEMEETUPINNEWGROUP"
            case .createMeetup: return "CREATEMEETUP"
            case .meetupSettings: return "MEETUPSETTINGS"
            case .chat: return "CHAT"
            case .demo: return "DEMO"
            case .unknown: return "UNKNOWN"
            }
        }
    }
    
    var trackingName: String {
        switch self {
        case .register: return "REGISTER"
        case .main(let state): return "MAIN>\(state.trackingName)"
        }
    }
}
