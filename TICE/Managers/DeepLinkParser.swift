//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import PromiseKit

enum DeepLinkParserError: LocalizedError {
    case invalidState
    case invalidDeepLink
    case meetupNotFound
    case shallowLink
}

extension URL {
    func appendingPathComponents(_ components: [String]) -> URL {
        if components.isEmpty { return self }
        let restComponents = [String](components[1...])
        return appendingPathComponent(components[0]).appendingPathComponents(restComponents)
    }
}

class DeepLinkParser: DeepLinkParserType {
    
    let baseURL: URL
    let teamManager: TeamManagerType
    let meetupManager: MeetupManagerType
    let groupStorageManager: GroupStorageManagerType
    
    init(teamManager: TeamManagerType, meetupManager: MeetupManagerType, groupStorageManager: GroupStorageManagerType, baseURL: URL) {
        self.teamManager = teamManager
        self.meetupManager = meetupManager
        self.groupStorageManager = groupStorageManager
        self.baseURL = baseURL
    }
    
    func deepLink(state: AppState) throws -> URL {
        switch state {
        case .main(.team(team: let groupId)):
            return baseURL.appendingPathComponents(["group", groupId.uuidString])
        case .main(.groups):
            return baseURL.appendingPathComponent("groups")
        case .main(.chat(team: let groupId)):
            return baseURL.appendingPathComponents(["group", groupId.uuidString, "chat"])
        case .main(.teamSettings(team: let groupId)):
            return baseURL.appendingPathComponents(["group", groupId.uuidString, "info"])
        case .main(.meetupSettings(team: let groupId, meetup: let meetupId)):
            return baseURL.appendingPathComponents(["group", groupId.uuidString, "meetup", meetupId.uuidString])
        default:
            throw DeepLinkParserError.invalidState
        }
    }
    
    func state(url: URL) -> Promise<AppState> {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            logger.error("Invalid invitation url")
            return .init(error: DeepLinkParserError.invalidDeepLink)
        }
        
        components.fragment = nil
        let fail = { () -> Promise<AppState> in
            logger.error("Invalid invitation url: \(components.url?.absoluteString ?? "n/a")")
            return .init(error: DeepLinkParserError.invalidDeepLink)
        }
        
        guard url.pathComponents.count > 1 else {
            logger.error("Deep link just into app, staying in current state.")
            return .init(error: DeepLinkParserError.shallowLink)
        }
        
        switch url.pathComponents[1] {
        case "group":
            guard url.pathComponents.count > 2,
                let groupId = GroupId(uuidString: url.pathComponents[2]) else {
                return fail()
            }
            return state(groupId: groupId, path: [String](url.pathComponents[3...]), fragment: url.fragment)
        case "settings":
            return .value(.main(.settings))
        default:
            return fail()
        }
    }
    
    func state(groupId: GroupId, path: [String], fragment: String?) -> Promise<AppState> {
        guard let resolvedTeam = teamManager.teamWith(groupId: groupId) else {
            return team(groupId: groupId, path: path, fragment: fragment).map { AppState.main(.join(team: $0)) }
        }
        
        guard !path.isEmpty else {
            return .value(.main(.team(team: groupId)))
        }
        
        switch path[0] {
        case "chat":
            return .value(.main(.chat(team: groupId)))
        case "info":
            return .value(.main(.teamSettings(team: groupId)))
        case "meetup":
            return stateForMeetup(team: resolvedTeam, path: [String](path.dropFirst()), fragment: fragment)
        default:
            return .value(.main(.team(team: groupId)))
        }
    }
    
    func stateForMeetup(team: Team, path: [String], fragment: String?) -> Promise<AppState> {
        guard !path.isEmpty, let meetupId = GroupId(uuidString: path[0]) else {
            logger.error("Invalid deep link for meetup")
            return .init(error: DeepLinkParserError.invalidDeepLink)
        }

        return firstly { () -> Promise<AppState> in
            guard let meetup = try groupStorageManager.meetupIn(team: team),
                meetup.groupId == meetupId else {
                throw DeepLinkParserError.meetupNotFound
            }

            return .value(.main(.meetupSettings(team: team.groupId, meetup: meetup.groupId)))
        }
    }
    
    func team(url: URL) -> Promise<Team> {
        guard url.pathComponents.count >= 3,
            let groupId = GroupId(uuidString: url.pathComponents[2]) else {
                logger.error("Invalid URL for public group")
                return .init(error: DeepLinkParserError.invalidDeepLink)
        }
        
        return team(groupId: groupId, path: [String](url.pathComponents[3...]), fragment: url.fragment)
    }
    
    func team(groupId: GroupId, path: [String], fragment: String?) -> Promise<Team> {
        guard let fragment = fragment,
            let groupKey = Data(base64URLEncoded: fragment) else {
            logger.error("Invalid deep link for public group")
            return .init(error: DeepLinkParserError.invalidDeepLink)
        }

        return teamManager.getOrFetchTeam(groupId: groupId, groupKey: groupKey)
    }
}
