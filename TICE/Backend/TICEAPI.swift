//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import PromiseKit
import TICEAPIModels

protocol TICEAPI {

    func createUser(publicKeys: UserPublicKeys, platform: Platform, deviceId: Data, verificationCode: String, publicName: String?) -> Promise<CreateUserResponse>

    func updateUser(userId: UserId, publicKeys: UserPublicKeys?, deviceId: Data?, verificationCode: String?, publicName: String?) -> Promise<Void>

    func verify(deviceId: Data) -> Promise<Void>
    func deleteUser(userId: UserId) -> Promise<Void>
    func getUser(userId: UserId) -> Promise<GetUserResponse>
    func getUserKeys(userId: UserId) -> Promise<GetUserPublicKeysResponse>

    func createGroup(userId: UserId, type: GroupType, joinMode: JoinMode, permissionMode: PermissionMode, groupId: GroupId, parentGroup: ParentGroup?, selfSignedAdminCertificate: Certificate, encryptedSettings: Ciphertext, encryptedInternalSettings: Ciphertext) -> Promise<CreateGroupResponse>
    func getGroupInformation(groupId: GroupId, groupTag: GroupTag?) -> Promise<GroupInformationResponse>
    func getGroupInternals(groupId: GroupId, serverSignedMembershipCertificate: Certificate, groupTag: GroupTag?) -> Promise<GroupInternalsResponse>
    func joinGroup(groupId: GroupId, selfSignedMembershipCertificate: Certificate, serverSignedAdminCertificate: Certificate?, adminSignedMembershipCertificate: Certificate?, groupTag: GroupTag) -> Promise<JoinGroupResponse>
    func addGroupMember(groupId: GroupId, userId: UserId, encryptedMembership: Ciphertext, serverSignedMembershipCertificate: Certificate, newTokenKey: SecretKey, groupTag: GroupTag, notificationRecipients: [NotificationRecipient]) -> Promise<UpdatedEtagResponse>
    func updateGroupMember(groupId: GroupId, userId: UserId, encryptedMembership: Ciphertext, serverSignedMembershipCertificate: Certificate, tokenKey: SecretKey, groupTag: GroupTag, notificationRecipients: [NotificationRecipient]) -> Promise<UpdatedEtagResponse>
    func deleteGroupMember(groupId: GroupId, userId: UserId, userServerSignedMembershipCertificate: Certificate, ownServerSignedMembershipCertificate: Certificate, tokenKey: SecretKey, groupTag: GroupTag, notificationRecipients: [NotificationRecipient]) -> Promise<UpdatedEtagResponse>
    func deleteGroup(groupId: GroupId, serverSignedAdminCertificate: Certificate, groupTag: GroupTag, notificationRecipients: [NotificationRecipient]) -> Promise<Void>
    func updateSettings(groupId: GroupId, encryptedSettings: Ciphertext, serverSignedMembershipCertificate: Certificate, groupTag: GroupTag, notificationRecipients: [NotificationRecipient]) -> Promise<UpdatedEtagResponse>
    func updateInternalSettings(groupId: GroupId, encryptedInternalSettings: Ciphertext, serverSignedMembershipCertificate: Certificate, groupTag: GroupTag, notificationRecipients: [NotificationRecipient]) -> Promise<UpdatedEtagResponse>

    func message(id: MessageId, senderId: UserId, timestamp: Date, encryptedMessage: Ciphertext, serverSignedMembershipCertificate: Certificate, recipients: Set<Recipient>, priority: MessagePriority, collapseId: String?) -> Promise<Void>
    func getMessages() -> Promise<GetMessagesResponse>
    
    func renewCertificate(_ certificate: Certificate) -> Promise<RenewCertificateResponse>
}
