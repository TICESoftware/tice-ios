//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation

struct Membership: Codable, Equatable {
    let userId: UserId
    let groupId: GroupId
    let publicSigningKey: PublicKey
    let admin: Bool

    var selfSignedMembershipCertificate: Certificate?
    var serverSignedMembershipCertificate: Certificate
    var adminSignedMembershipCertificate: Certificate?

    init(userId: UserId, publicSigningKey: PublicKey, groupId: GroupId, admin: Bool, selfSignedMembershipCertificate: Certificate? = nil, serverSignedMembershipCertificate: Certificate, adminSignedMembershipCertificate: Certificate? = nil) {
        self.userId = userId
        self.publicSigningKey = publicSigningKey
        self.groupId = groupId
        self.admin = admin
        self.selfSignedMembershipCertificate = selfSignedMembershipCertificate
        self.serverSignedMembershipCertificate = serverSignedMembershipCertificate
        self.adminSignedMembershipCertificate = adminSignedMembershipCertificate
    }
}
