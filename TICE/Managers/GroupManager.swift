//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import PromiseKit
import TICEAPIModels
import CoreLocation

class GroupManager: GroupManagerType {

    let signedInUser: SignedInUser
    let groupStorageManager: GroupStorageManagerType
    let cryptoManager: CryptoManagerType
    let authManager: AuthManagerType
    let backend: TICEAPI
    let mailbox: MailboxType
    let encoder: JSONEncoder

    init(signedInUser: SignedInUser, groupStorageManager: GroupStorageManagerType, cryptoManager: CryptoManagerType, authManager: AuthManagerType, backend: TICEAPI, mailbox: MailboxType, encoder: JSONEncoder) {
        self.signedInUser = signedInUser
        self.groupStorageManager = groupStorageManager
        self.cryptoManager = cryptoManager
        self.authManager = authManager
        self.backend = backend
        self.mailbox = mailbox
        self.encoder = encoder
    }

    func addUserMember(into group: Group, admin: Bool, serverSignedMembershipCertificate: Certificate) -> Promise<(Membership, GroupTag)> {
        return firstly { () -> Promise<(Membership, GroupTag)> in
            let selfSignedMembershipCertificate = try authManager.createUserSignedMembershipCertificate(userId: signedInUser.userId, groupId: group.groupId, admin: admin, issuerUserId: signedInUser.userId, signingKey: signedInUser.privateSigningKey)
            let membership = Membership(userId: signedInUser.userId, publicSigningKey: signedInUser.publicSigningKey, groupId: group.groupId, admin: admin, selfSignedMembershipCertificate: selfSignedMembershipCertificate, serverSignedMembershipCertificate: serverSignedMembershipCertificate)

            let membershipData = try encoder.encode(membership)
            let encryptedMembership = try cryptoManager.encrypt(membershipData, secretKey: group.groupKey)

            let tokenKey = try self.cryptoManager.tokenKeyForGroup(groupKey: group.groupKey, user: signedInUser)

            let notificationRecipients = try self.notificationRecipients(groupId: group.groupId, alert: true)

            return self.backend.addGroupMember(groupId: group.groupId, userId: signedInUser.userId, encryptedMembership: encryptedMembership, serverSignedMembershipCertificate: serverSignedMembershipCertificate, newTokenKey: tokenKey, groupTag: group.tag, notificationRecipients: notificationRecipients).map { (membership, $0.groupTag) }
        }
    }

    func leave(_ group: Group) -> Promise<GroupTag> {
        return firstly { () -> Promise<GroupTag> in
            let membership = try groupStorageManager.loadMembership(userId: signedInUser.userId, groupId: group.groupId)

            guard !membership.admin else {
                throw GroupManagerError.lastAdmin
            }

            let notificationRecipients = try self.notificationRecipients(groupId: group.groupId, alert: true)
            let tokenKey = try self.cryptoManager.tokenKeyForGroup(groupKey: group.groupKey, user: self.signedInUser)

            logger.debug("Leave group: tokenKey \(tokenKey), derived from group key \(group.groupKey) and public signing key \(self.signedInUser.publicSigningKey)")

            return self.backend.deleteGroupMember(groupId: group.groupId, userId: self.signedInUser.userId, userServerSignedMembershipCertificate: membership.serverSignedMembershipCertificate, ownServerSignedMembershipCertificate: membership.serverSignedMembershipCertificate, tokenKey: tokenKey, groupTag: group.tag, notificationRecipients: notificationRecipients).map { $0.groupTag }
        }
    }

    func deleteGroupMember(_ membership: Membership, from group: Group, serverSignedMembershipCertificate: Certificate) -> Promise<Void> {
        return firstly { () -> Promise<UpdatedEtagResponse> in
            guard !membership.admin else {
                throw GroupManagerError.lastAdmin
            }

            let notificationRecipients = try self.notificationRecipients(groupId: group.groupId, alert: true)

            let user = try groupStorageManager.user(for: membership)
            let tokenKey = try self.cryptoManager.tokenKeyForGroup(groupKey: group.groupKey, user: user)

            logger.debug("Leave group: tokenKey \(tokenKey), derived from group key \(group.groupKey) and public signing key \(membership.publicSigningKey)")

            return self.backend.deleteGroupMember(groupId: group.groupId, userId: membership.userId, userServerSignedMembershipCertificate: membership.serverSignedMembershipCertificate, ownServerSignedMembershipCertificate: serverSignedMembershipCertificate, tokenKey: tokenKey, groupTag: group.tag, notificationRecipients: notificationRecipients)
        }.done { groupTagResponse in
            try self.groupStorageManager.removeMembership(userId: membership.userId, groupId: group.groupId, updatedGroupTag: groupTagResponse.groupTag)
        }
    }

    // MARK: Helpers

    func notificationRecipients(groupId: GroupId, alert: Bool) throws -> [NotificationRecipient] {
        let memberships = try groupStorageManager.loadMemberships(groupId: groupId)
        let filteredMemberships = memberships.filter { $0.userId != signedInUser.userId }
        return filteredMemberships.map { NotificationRecipient(userId: $0.userId, serverSignedMembershipCertificate: $0.serverSignedMembershipCertificate, priority: alert ? .alert : .background) }
    }

    // MARK: Group messages

    func send(payloadContainer: PayloadContainer, to group: Group, collapseId: Envelope.CollapseIdentifier?, priority: MessagePriority) -> Promise<Void> {
        firstly { () -> Promise<Void> in
            let ownMembership = try groupStorageManager.loadMembership(userId: signedInUser.userId, groupId: group.groupId)
            let memberships = try groupStorageManager.loadMemberships(groupId: group.groupId).filter { $0.userId != signedInUser.userId }
            return mailbox.send(payloadContainer: payloadContainer, to: memberships, serverSignedMembershipCertificate: ownMembership.serverSignedMembershipCertificate, priority: priority, collapseId: collapseId)
        }
    }

    func sendGroupUpdateNotification(to group: Group, action: GroupUpdate.Action) -> Promise<Void> {
        let groupUpdate = GroupUpdate(groupId: group.groupId, action: action)
        let payloadContainer = PayloadContainer(payloadType: .groupUpdateV1, payload: groupUpdate)

        return send(payloadContainer: payloadContainer, to: group, collapseId: nil, priority: .alert)
    }
}

enum GroupManagerError: LocalizedError {
    case lastAdmin

    var errorDescription: String? {
        switch self {
        case .lastAdmin: return "Cannot remove last admin from group."
        }
    }
}
