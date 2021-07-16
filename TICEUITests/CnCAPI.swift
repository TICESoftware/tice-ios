//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import ConvAPI
import PromiseKit
import TICEAPIModels

protocol CnCAPI {
    func createUser() -> Promise<CreateUserResponse>
    func changeUserName(userId: UserId, name: String?) -> Promise<Void>
    func getUserKeys(userId: UserId) -> Promise<GetUserPublicKeysResponse>
    func createGroup(userId: UserId, type: GroupType, joinMode: JoinMode, permissionMode: PermissionMode, parent: GroupId?, settings: GroupSettings) -> Promise<CnCCreateGroupResponse>
    func joinGroup(userId: UserId, groupId: GroupId, groupKey: String) -> Promise<Void>
    func sendMessage(userId: UserId, groupId: GroupId, payloadContainer: PayloadContainer) -> Promise<Void>
    func updateGroupSettings(userId: UserId, groupId: GroupId, settings: GroupSettings) -> Promise<Void>
    func sendLocationUpdate(userId: UserId, groupId: GroupId, location: Location) -> Promise<Void>
    func updateMeetingPoint(userId: UserId, meetupId: GroupId, latitude: Double, longitude: Double) -> Promise<Void>
    func getGroupMembers(userId: UserId, groupId: GroupId) -> Promise<CnCGetGroupMembersResponse>
}

class CnC: CnCAPI {

    let backend: Backend

    init(backend: Backend) {
        self.backend = backend
    }

    // MARK: User

    func createUser() -> Promise<CreateUserResponse> {
        print(#function)
        return backend.request(method: .POST, resource: "/user")
    }
    
    func changeUserName(userId: UserId, name: String?) -> Promise<Void> {
        print("\(#function) \(userId) \(name ?? "N/A")")
        let path = "/user/\(userId)/changeName"
        let body = CnCChangePublicName(publicName: name)
        return backend.request(method: .POST, resource: path, body: body)
    }

    func getUserKeys(userId: UserId) -> Promise<GetUserPublicKeysResponse> {
        print("\(#function) \(userId)")
        let path = "/user/\(userId)/getKeys"
        let body = CnCGetUserKeys(userId: userId)
        return backend.request(method: .POST, resource: path, body: body)
    }

    func createGroup(userId: UserId, type: GroupType, joinMode: JoinMode, permissionMode: PermissionMode, parent: GroupId?, settings: GroupSettings) -> Promise<CnCCreateGroupResponse> {
        print("\(#function) \(settings)")
        let path = "/user/\(userId)/group"
        let body = CnCCreateGroupRequest(type: type, joinMode: joinMode, permissionMode: permissionMode, parent: parent, settings: settings)
        return backend.request(method: .POST, resource: path, body: body)
    }

    func joinGroup(userId: UserId, groupId: GroupId, groupKey: String) -> Promise<Void> {
        print("\(#function) \(userId) -> \(groupId)")
        let path = "/user/\(userId)/joinGroup"
        let body = CnCJoinGroupRequest(groupId: groupId, groupKey: groupKey)
        return backend.request(method: .POST, resource: path, body: body)
    }
    
    func updateGroupSettings(userId: UserId, groupId: GroupId, settings: GroupSettings) -> Promise<Void> {
        print("\(#function) \(settings)")
        let path = "/user/\(userId)/updateGroup"
        let body = CnCSettingsUpdate(groupId: groupId, settings: settings)
        return backend.request(method: .POST, resource: path, body: body)
    }

    func sendMessage(userId: UserId, groupId: GroupId, payloadContainer: PayloadContainer) -> Promise<Void> {
        print("\(#function) \(payloadContainer)")
        let path = "/user/\(userId)/message"
        let body = CnCSendEncryptedMessageRequest(groupId: groupId, payloadContainer: payloadContainer)
        return backend.request(method: .POST, resource: path, body: body)
    }
    
    func sendLocationUpdate(userId: UserId, groupId: GroupId, location: Location) -> Promise<Void> {
        print("\(#function) \(userId)")
        let path = "/user/\(userId)/locationUpdate"
        let body = CnCLocationUpdate(groupId: groupId, latitude: location.latitude, longitude: location.longitude, altitude: location.altitude, horizontalAccuracy: location.horizontalAccuracy, verticalAccuracy: location.verticalAccuracy)
        return backend.request(method: .POST, resource: path, body: body)
    }
    
    func updateMeetingPoint(userId: UserId, meetupId: GroupId, latitude: Double, longitude: Double) -> Promise<Void> {
        print(#function)
        let path = "/user/\(userId)/updateMeetupInternalSettings"
        let body = CnCMeetupInternalSettingsUpdate(groupId: meetupId, meetingPoint: CnCMeetupInternalSettingsUpdate.MeetingPoint(latitude: latitude, longitude: longitude))
        return backend.request(method: .POST, resource: path, body: body)
    }
    
    func getGroupMembers(userId: UserId, groupId: GroupId) -> Promise<CnCGetGroupMembersResponse> {
        print("\(#function) \(userId)")
        let path = "/user/\(userId)/groupMembers"
        let body = CnCGetGroupMembers(groupId: groupId)
        return backend.request(method: .POST, resource: path, body: body)
    }
}
