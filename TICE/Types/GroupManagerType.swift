//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import PromiseKit
import TICEAPIModels

protocol GroupManagerType {
    func leave(_ group: Group) -> Promise<GroupTag>
    func deleteGroupMember(_ membership: Membership, from group: Group, serverSignedMembershipCertificate: Certificate) -> Promise<Void>
    func send(payloadContainer: PayloadContainer, to group: Group, collapseId: Envelope.CollapseIdentifier?, priority: MessagePriority) -> Promise<Void>
    func sendGroupUpdateNotification(to group: Group, action: GroupUpdate.Action) -> Promise<Void>
    func addUserMember(into group: Group, admin: Bool, serverSignedMembershipCertificate: Certificate) -> Promise<(Membership, GroupTag)>
    func notificationRecipients(groupId: GroupId, alert: Bool) throws -> [NotificationRecipient]
}
