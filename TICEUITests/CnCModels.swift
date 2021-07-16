//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels

struct CnCChangePublicName: Codable {
    let publicName: String?
}

struct CnCDeleteUser: Codable {
    let userId: UserId
}

struct CnCGetUserKeys: Codable {
    let userId: UserId
}

struct CnCCreateGroupRequest: Codable {
    let type: GroupType
    let joinMode: JoinMode
    let permissionMode: PermissionMode
    let parent: GroupId?
    let settings: GroupSettings
}

struct CnCCreateGroupResponse: Codable {
    let groupId: GroupId
    let groupKey: String
}

struct CnCJoinGroupRequest: Codable {
    let groupId: GroupId
    let groupKey: String
}

struct CnCJoinGroupResponse: Codable {
    let type: GroupType
    let joinMode: JoinMode
    let permissionMode: PermissionMode
    let parent: GroupId?
    let settings: GroupSettings
}

struct CnCSendEncryptedMessageRequest: Codable {
    let groupId: GroupId
    let payloadContainer: PayloadContainer
}

struct CnCLeaveGroupRequest: Codable {
    let groupId: GroupId
}

struct CnCDeleteGroupRequest: Codable {
    let groupId: GroupId
}

struct CnCLocationUpdate: Codable {
    let groupId: GroupId
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let horizontalAccuracy: Double
    let verticalAccuracy: Double
}

struct CnCSettingsUpdate: Codable {
    let groupId: GroupId
    let settings: GroupSettings
}

struct CnCMeetupInternalSettingsUpdate: Codable {
    struct MeetingPoint: Codable {
        let latitude: Double
        let longitude: Double
    }

    let groupId: GroupId
    let meetingPoint: MeetingPoint?
}

struct CnCGetGroupMembers: Codable {
    let groupId: GroupId
}

struct CnCGetGroupMembersResponse: Codable {
    let members: [Member]
}
