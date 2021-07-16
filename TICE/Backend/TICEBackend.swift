//
//  Copyright © 2018 TICE Software UG (haftungsbeschränkt). All rights reserved.
//

import Foundation
import ConvAPI
import PromiseKit
import TICEAPIModels
import TICEAuth
import Version

struct EmptyResponse: Empty {
    public init() {}
}

public enum BackendError: LocalizedError {
    case notModified
    case unauthorized

    public var errorDescription: String? {
        switch self {
        case .notModified: return "Not modified"
        case .unauthorized: return "Unauthorized"
        }
    }
}

class TICEBackend: Backend {

    let authManager: AuthManagerType
    let signedInUserManager: SignedInUserManagerType

    let clientVersion: Version
    let clientBuild: Int
    let clientPlatform: String

    init(api: API, baseURL: URL, clientVersion: Version, clientBuild: Int, clientPlatform: String, authManager: AuthManagerType, signedInUserManager: SignedInUserManagerType) {
        self.authManager = authManager
        self.signedInUserManager = signedInUserManager

        self.clientVersion = clientVersion
        self.clientBuild = clientBuild
        self.clientPlatform = clientPlatform

        super.init(api: api, baseURL: baseURL)
    }
}

extension TICEBackend: TICEAPI {

    enum HeaderKey: String {
        case authentication = "X-Authorization"
        case authorization = "X-ServerSignedMembershipCertificate"
        case groupTag = "X-GroupTag"
        case platform = "X-Platform"
        case version = "X-Version"
        case build = "X-Build"
    }

    func clientHeaders() -> [String: String] {
        return [HeaderKey.platform.rawValue: clientPlatform,
                HeaderKey.version.rawValue: "\(clientVersion)",
                HeaderKey.build.rawValue: "\(clientBuild)"]
    }

    func authenticationHeader() throws -> Certificate {
        let signedInUser = try signedInUserManager.requireSignedInUser()
        let certificate = try authManager.generateAuthHeader(signingKey: signedInUser.privateSigningKey,
                                                               userId: signedInUser.userId)
        return certificate
    }

    // MARK: User

    func createUser(publicKeys: UserPublicKeys, platform: Platform, deviceId: Data, verificationCode: String, publicName: String?) -> Promise<CreateUserResponse> {
        let deviceIdString = deviceId.reduce("", { $0 + String(format: "%02X", $1) })
        let body = CreateUserRequest(publicKeys: publicKeys, platform: platform, deviceId: deviceIdString, verificationCode: verificationCode, publicName: publicName)
        let headers = self.clientHeaders()
        return request(method: .POST, resource: "/user", headers: headers, body: body)
    }

    func updateUser(userId: UserId, publicKeys: UserPublicKeys?, deviceId: Data?, verificationCode: String? = nil, publicName: String?) -> Promise<Void> {
        let deviceIdString = deviceId?.reduce("", { $0 + String(format: "%02X", $1) })
        let request = UpdateUserRequest(publicKeys: publicKeys, deviceId: deviceIdString, verificationCode: verificationCode, publicName: publicName)
        return updateUser(userId: userId, updateUserRequest: request)
    }

    private func updateUser(userId: UserId, updateUserRequest: UpdateUserRequest) -> Promise<Void> {
        return firstly { () -> Promise<Void> in
            var headers = self.clientHeaders()
            headers[HeaderKey.authentication.rawValue] = try authenticationHeader()
            return self.request(method: .PUT, resource: "/user/\(userId)", headers: headers, body: updateUserRequest)
        }
    }

    func verify(deviceId: Data) -> Promise<Void> {
        let deviceIdString = deviceId.reduce("", { $0 + String(format: "%02X", $1) })
        let body = VerifyRequest(platform: .iOS, deviceId: deviceIdString)
        let headers = self.clientHeaders()
        return request(method: .POST, resource: "/verify", headers: headers, body: body)
    }

    func deleteUser(userId: UserId) -> Promise<Void> {
        return firstly { () -> Promise<Void> in
            var headers = self.clientHeaders()
            headers[HeaderKey.authentication.rawValue] = try authenticationHeader()
            return self.request(method: .DELETE, resource: "/user/\(userId)", headers: headers)
        }
    }

    func getUser(userId: UserId) -> Promise<GetUserResponse> {
        return firstly { () -> Promise<GetUserResponse> in
            var headers = self.clientHeaders()
            headers[HeaderKey.authentication.rawValue] = try authenticationHeader()
            return self.request(method: .GET, resource: "/user/\(userId)", headers: headers)
        }
    }

    func getUserKeys(userId: UserId) -> Promise<GetUserPublicKeysResponse> {
        return firstly { () -> Promise<GetUserPublicKeysResponse> in
            var headers = self.clientHeaders()
            headers[HeaderKey.authentication.rawValue] = try authenticationHeader()
            return self.request(method: .POST, resource: "/user/\(userId)/keys", headers: headers)
        }
    }

    // MARK: Group

    func createGroup(userId: UserId, type: GroupType, joinMode: JoinMode, permissionMode: PermissionMode, groupId: GroupId, parentGroup: ParentGroup?, selfSignedAdminCertificate: Certificate, encryptedSettings: Ciphertext, encryptedInternalSettings: Ciphertext) -> Promise<CreateGroupResponse> {
        return firstly { () -> Promise<CreateGroupResponse> in
            var headers = self.clientHeaders()
            headers[HeaderKey.authentication.rawValue] = try authenticationHeader()
            let body = CreateGroupRequest(groupId: groupId, type: type, joinMode: joinMode, permissionMode: permissionMode, selfSignedAdminCertificate: selfSignedAdminCertificate, encryptedSettings: Data(encryptedSettings), encryptedInternalSettings: Data(encryptedInternalSettings), parent: parentGroup)

            return self.request(method: .POST, resource: "/group", headers: headers, body: body)
        }
    }

    func getGroupInformation(groupId: GroupId, groupTag: GroupTag?) -> Promise<GroupInformationResponse> {
        var headers = self.clientHeaders()

        if let groupTag = groupTag {
            headers[HeaderKey.groupTag.rawValue] = groupTag
        }

        return firstly { () -> Promise<GroupInformationResponse> in
            headers[HeaderKey.authentication.rawValue] = try authenticationHeader()
            return self.request(method: .GET, resource: "/group/\(groupId)", headers: headers)
        }.recover { error -> Promise<GroupInformationResponse> in
            guard case RequestError.emptyErrorResponse(httpStatusCode: let statusCode) = error,
                statusCode == 304 else {
                    throw error
            }
            throw BackendError.notModified
        }
    }

    func getGroupInternals(groupId: GroupId, serverSignedMembershipCertificate: Certificate, groupTag: GroupTag?) -> Promise<GroupInternalsResponse> {
        var headers = self.clientHeaders()
        headers[HeaderKey.authorization.rawValue] = serverSignedMembershipCertificate

        if let groupTag = groupTag {
            headers[HeaderKey.groupTag.rawValue] = groupTag
        }

        return firstly { () -> Promise<GroupInternalsResponse> in
            headers[HeaderKey.authentication.rawValue] = try authenticationHeader()
            return self.request(method: .GET, resource: "/group/\(groupId)/internals", headers: headers)
        }.recover { error -> Promise<GroupInternalsResponse> in
            guard let apiError = error as? APIError else {
                    throw error
            }
            switch apiError.type {
            case .notModified:
                throw BackendError.notModified
            case .authenticationFailed:
                throw BackendError.unauthorized
            default:
                throw error
            }
        }
    }

    func joinGroup(groupId: GroupId, selfSignedMembershipCertificate: Certificate, serverSignedAdminCertificate: Certificate?, adminSignedMembershipCertificate: Certificate?, groupTag: GroupTag) -> Promise<JoinGroupResponse> {
        var headers = clientHeaders()
        headers[HeaderKey.groupTag.rawValue] = groupTag

        return firstly { () -> Promise<JoinGroupResponse> in
            headers[HeaderKey.authentication.rawValue] = try authenticationHeader()
            let body = JoinGroupRequest(selfSignedMembershipCertificate: selfSignedMembershipCertificate, serverSignedAdminCertificate: serverSignedAdminCertificate, adminSignedMembershipCertificate: adminSignedMembershipCertificate)

            return self.request(method: .POST, resource: "/group/\(groupId)/request", headers: headers, body: body)
        }
    }

    func addGroupMember(groupId: GroupId, userId: UserId, encryptedMembership: Ciphertext, serverSignedMembershipCertificate: Certificate, newTokenKey: SecretKey, groupTag: GroupTag, notificationRecipients: [NotificationRecipient]) -> Promise<UpdatedEtagResponse> {
        var headers = clientHeaders()

        headers[HeaderKey.authorization.rawValue] = serverSignedMembershipCertificate
        headers[HeaderKey.groupTag.rawValue] = groupTag

        return firstly { () -> Promise<UpdatedEtagResponse> in
            headers[HeaderKey.authentication.rawValue] = try authenticationHeader()
            let body = AddGroupMemberRequest(encryptedMembership: Data(encryptedMembership), userId: userId, newTokenKey: newTokenKey.base64URLEncodedString(), notificationRecipients: notificationRecipients)

            return self.request(method: .POST, resource: "/group/\(groupId)/member", headers: headers, body: body)
        }
    }
    
    func updateGroupMember(groupId: GroupId, userId: UserId, encryptedMembership: Ciphertext, serverSignedMembershipCertificate: Certificate, tokenKey: SecretKey, groupTag: GroupTag, notificationRecipients: [NotificationRecipient]) -> Promise<UpdatedEtagResponse> {
        var headers = clientHeaders()

        headers[HeaderKey.authorization.rawValue] = serverSignedMembershipCertificate
        headers[HeaderKey.groupTag.rawValue] = groupTag
        
        let body = UpdateGroupMemberRequest(encryptedMembership: encryptedMembership, userId: userId, notificationRecipients: notificationRecipients)
        
        return firstly { () -> Promise<UpdatedEtagResponse> in
            headers[HeaderKey.authentication.rawValue] = try authenticationHeader()
            return request(method: .PUT, resource: "/group/\(groupId)/member/\(tokenKey.base64URLEncodedString())", headers: headers, body: body)
        }
    }

    func deleteGroupMember(groupId: GroupId, userId: UserId, userServerSignedMembershipCertificate: Certificate, ownServerSignedMembershipCertificate: Certificate, tokenKey: SecretKey, groupTag: GroupTag, notificationRecipients: [NotificationRecipient]) -> Promise<UpdatedEtagResponse> {
        var headers = clientHeaders()

        headers[HeaderKey.groupTag.rawValue] = groupTag
        headers[HeaderKey.authorization.rawValue] = ownServerSignedMembershipCertificate

        return firstly { () -> Promise<UpdatedEtagResponse> in
            headers[HeaderKey.authentication.rawValue] = try authenticationHeader()
            let body = DeleteGroupMemberRequest(userId: userId, serverSignedMembershipCertificate: userServerSignedMembershipCertificate, notificationRecipients: notificationRecipients)

            return self.request(method: .DELETE, resource: "/group/\(groupId)/member/\(tokenKey.base64URLEncodedString())", headers: headers, body: body)
        }
    }

    func deleteGroup(groupId: GroupId, serverSignedAdminCertificate: Certificate, groupTag: GroupTag, notificationRecipients: [NotificationRecipient]) -> Promise<Void> {
        var headers = clientHeaders()
        headers[HeaderKey.groupTag.rawValue] = groupTag
        headers[HeaderKey.authorization.rawValue] = serverSignedAdminCertificate

        return firstly { () -> Promise<Void> in
            headers[HeaderKey.authentication.rawValue] = try authenticationHeader()
            let body = DeleteGroupRequest(serverSignedAdminCertificate: serverSignedAdminCertificate, notificationRecipients: notificationRecipients)
            return self.request(method: .DELETE, resource: "/group/\(groupId)", headers: headers, body: body)
        }
    }

    func updateSettings(groupId: GroupId, encryptedSettings: Ciphertext, serverSignedMembershipCertificate: Certificate, groupTag: GroupTag, notificationRecipients: [NotificationRecipient]) -> Promise<UpdatedEtagResponse> {
        var headers = clientHeaders()
        headers[HeaderKey.groupTag.rawValue] = groupTag
        headers[HeaderKey.authorization.rawValue] = serverSignedMembershipCertificate

        return firstly { () -> Promise<UpdatedEtagResponse> in
            headers[HeaderKey.authentication.rawValue] = try authenticationHeader()
            let body = UpdateGroupInformationRequest(newSettings: Data(encryptedSettings), notificationRecipients: notificationRecipients)
            return self.request(method: .PUT, resource: "/group/\(groupId)", headers: headers, body: body)
        }
    }

    func updateInternalSettings(groupId: GroupId, encryptedInternalSettings: Ciphertext, serverSignedMembershipCertificate: Certificate, groupTag: GroupTag, notificationRecipients: [NotificationRecipient]) -> Promise<UpdatedEtagResponse> {
        var headers = clientHeaders()
        headers[HeaderKey.authorization.rawValue] = serverSignedMembershipCertificate
        headers[HeaderKey.groupTag.rawValue] = groupTag

        return firstly { () -> Promise<UpdatedEtagResponse> in
            headers[HeaderKey.authentication.rawValue] = try authenticationHeader()
            let body = UpdateGroupInternalsRequest(newInternalSettings: Data(encryptedInternalSettings), notificationRecipients: notificationRecipients)
            return self.request(method: .PUT, resource: "/group/\(groupId)/internals", headers: headers, body: body)
        }
    }

    // MARK: Message

    func message(id: MessageId, senderId: UserId, timestamp: Date, encryptedMessage: Ciphertext, serverSignedMembershipCertificate: Certificate, recipients: Set<Recipient>, priority: MessagePriority, collapseId: String?) -> Promise<Void> {
        return firstly { () -> Promise<Void> in
            var headers = clientHeaders()
            headers[HeaderKey.authentication.rawValue] = try authenticationHeader()
            let body = SendMessageRequest(id: id, senderId: senderId, timestamp: timestamp, encryptedMessage: encryptedMessage, serverSignedMembershipCertificate: serverSignedMembershipCertificate, recipients: Array(recipients), priority: priority, collapseId: collapseId)

            return self.request(method: .POST, resource: "/message", headers: headers, body: body)
        }
    }

    func getMessages() -> Promise<GetMessagesResponse> {
        return firstly { () -> Promise<GetMessagesResponse> in
            var headers = clientHeaders()
            headers[HeaderKey.authentication.rawValue] = try authenticationHeader()
            return self.request(method: .GET, resource: "/message", headers: headers)
        }
    }
    
    // MARK: Certificates
    
    func renewCertificate(_ certificate: Certificate) -> Promise<RenewCertificateResponse> {
        var headers = clientHeaders()
        let body = RenewCertificateRequest(certificate: certificate)
        
        return firstly { () -> Promise<RenewCertificateResponse> in
            headers[HeaderKey.authentication.rawValue] = try authenticationHeader()
            return request(method: .POST, resource: "/certificates/renew", headers: headers, body: body)
        }
    }
}
