//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels

struct Team: Codable, Group {
    let groupId: GroupId
    let groupKey: SecretKey
    let owner: UserId
    let joinMode: JoinMode
    let permissionMode: PermissionMode
    var tag: GroupTag

    let url: URL
    var name: String?
    var meetupId: GroupId?
    var meetingPoint: Location?

    var shareURL: URL {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.path = url.relativePath
        components.fragment = groupKey.base64URLEncodedString()

        return components.url!
    }
}

public struct InternalTeamSettings: Hashable, Codable {
    var meetingPoint: Location?

    init(meetingPoint: Location?) {
        self.meetingPoint = meetingPoint
    }
}

extension Team: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.groupId == rhs.groupId
    }
}
