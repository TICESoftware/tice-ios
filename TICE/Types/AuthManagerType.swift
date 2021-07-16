//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAuth

protocol AuthManagerType {
    func createUserSignedMembershipCertificate(userId: UserId, groupId: GroupId, admin: Bool, issuerUserId: UserId, signingKey: PrivateKey) throws -> Certificate
    func membershipCertificateExpirationDate(certificate: Certificate) throws -> Date
    func generateAuthHeader(signingKey: PrivateKey, userId: UserId) throws -> Certificate
}

extension AuthManager: AuthManagerType { }
