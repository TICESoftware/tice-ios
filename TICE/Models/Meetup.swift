//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels
import CoreLocation

struct Meetup: Codable, Group {
    let groupId: GroupId
    let groupKey: SecretKey
    let owner: UserId
    let joinMode: JoinMode
    let permissionMode: PermissionMode
    var tag: GroupTag

    let teamId: GroupId
    var meetingPoint: Location?
    var locationSharingEnabled: Bool
}

struct InternalMeetupSettings: Codable {
    var location: Location?

    init(location: Location?) {
        self.location = location
    }
}
