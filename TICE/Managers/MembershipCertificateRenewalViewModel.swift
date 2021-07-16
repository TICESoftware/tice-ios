//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels
import UIKit
import PromiseKit

class MembershipCertificateRenewalViewModel: LoadingViewModelType {
    
    let groupStorageManager: GroupStorageManagerType
    let signedInUserManager: SignedInUserManagerType
    let cryptoManager: CryptoManagerType
    let authManager: AuthManagerType
    let backend: TICEAPI
    let coordinator: AppFlow
    let encoder: JSONEncoder
    let certificateValidityTimeRenewalThreshold: TimeInterval
    let tracker: TrackerType
    
    weak var delegate: LoadingViewController?

    init(groupStorageManager: GroupStorageManagerType, signedInUserManager: SignedInUserManagerType, cryptoManager: CryptoManagerType, authManager: AuthManagerType, backend: TICEAPI, coordinator: AppFlow, encoder: JSONEncoder, certificateValidityTimeRenewalThreshold: TimeInterval, tracker: TrackerType) {
        self.groupStorageManager = groupStorageManager
        self.signedInUserManager = signedInUserManager
        self.cryptoManager = cryptoManager
        self.authManager = authManager
        self.backend = backend
        self.coordinator = coordinator
        self.encoder = encoder
        self.certificateValidityTimeRenewalThreshold = certificateValidityTimeRenewalThreshold
        self.tracker = tracker
    }
    
    func enter() {
        guard let signedInUser = signedInUserManager.signedInUser else {
            logger.info("Skipping housekeeping as we have no signed in user")
            self.coordinator.finishHousekeeping()
            return
        }
        
        firstly { () -> Promise<Void> in
            renewCertificatesIfNecessary(signedInUser: signedInUser)
        }.catch { error in
            logger.error("An error occurred during housekeeping: \(error)")
        }.finally {
            self.coordinator.finishHousekeeping()
        }
    }

    private func renewCertificatesIfNecessary(signedInUser: SignedInUser) -> Promise<Void> {
        return firstly { () -> Promise<([Membership], [Result<Bool>])> in
            let memberships = try groupStorageManager.loadMemberships(userId: signedInUser.userId)

            let checkPromises = memberships.map { membership -> Promise<Bool> in
                return firstly { () -> Promise<Bool> in
                    let renewSelfSignedMembershipCertificate = try membership.selfSignedMembershipCertificate.map { try authManager.membershipCertificateExpirationDate(certificate: $0).timeIntervalSinceNow < certificateValidityTimeRenewalThreshold } ?? false
                    let renewServerSignedMembershipCertificate = try authManager.membershipCertificateExpirationDate(certificate: membership.serverSignedMembershipCertificate).timeIntervalSinceNow < certificateValidityTimeRenewalThreshold
                    
                    guard renewSelfSignedMembershipCertificate || renewServerSignedMembershipCertificate else {
                        logger.debug("No need to renew certificates for group \(membership.groupId).")
                        return Promise.value(false)
                    }
                    return Promise.value(true)
                }
            }
            
            return when(resolved: checkPromises).map { (memberships, $0) }
        }.then { (memberships: [Membership], renewals: [Result<Bool>]) -> Promise<([Membership], [Result<Void>])> in
            var membershipsToRenew: [Membership] = []
            for (membership, renewal) in zip(memberships, renewals) {
                switch renewal {
                case .rejected(let error):
                    logger.error("Failed to check for certificate renewal requirement in group \(membership.groupId): \(error)")
                    self.tracker.log(action: TrackerAction.error, category: TrackerCategory.membershipRenewal, detail: String(describing: error))
                case .fulfilled(let renew):
                    if renew { membershipsToRenew.append(membership) }
                }
            }
            
            let renewalPromises = membershipsToRenew.map { membership -> Promise<Void> in
                return firstly { () -> Promise<(Certificate, Certificate)> in
                    let renewedSelfSignedMembershipCertificate = try self.authManager.createUserSignedMembershipCertificate(userId: signedInUser.userId, groupId: membership.groupId, admin: membership.admin, issuerUserId: signedInUser.userId, signingKey: signedInUser.privateSigningKey)
                    return self.backend.renewCertificate(membership.serverSignedMembershipCertificate).map { (renewedSelfSignedMembershipCertificate, $0.certificate) }
                }.then { renewedSelfSignedMembershipCertificate, renewedServerSignedMembershipCertificate -> Promise<UpdatedEtagResponse> in
                    let renewedMembership = Membership(userId: membership.userId, publicSigningKey: membership.publicSigningKey, groupId: membership.groupId, admin: membership.admin, selfSignedMembershipCertificate: renewedSelfSignedMembershipCertificate, serverSignedMembershipCertificate: renewedServerSignedMembershipCertificate)
                    let group = try self.groupStorageManager.loadGroup(groupId: renewedMembership.groupId)
                    let membershipData = try self.encoder.encode(renewedMembership)
                    let encryptedMembership = try self.cryptoManager.encrypt(membershipData, secretKey: group.groupKey)
                    let tokenKey = try self.cryptoManager.tokenKeyForGroup(groupKey: group.groupKey, user: signedInUser)
                    
                    let memberships = try self.groupStorageManager.loadMemberships(groupId: renewedMembership.groupId)
                    let filteredMemberships = memberships.filter { $0.userId != signedInUser.userId }
                    let notificationRecipients = filteredMemberships.map { NotificationRecipient(userId: $0.userId, serverSignedMembershipCertificate: $0.serverSignedMembershipCertificate, priority: .background) }
                
                    return firstly {
                        self.backend.updateGroupMember(groupId: renewedMembership.groupId, userId: signedInUser.userId, encryptedMembership: encryptedMembership, serverSignedMembershipCertificate: renewedMembership.serverSignedMembershipCertificate, tokenKey: tokenKey, groupTag: group.tag, notificationRecipients: notificationRecipients)
                    }.get { _ in
                        try self.groupStorageManager.store(renewedMembership)
                    }
                }.done { updatedEtagResponse in
                    try self.groupStorageManager.updateGroupTag(groupId: membership.groupId, tag: updatedEtagResponse.groupTag)
                }
            }
            
            return when(resolved: renewalPromises).map { (memberships, $0) }
        }.done { memberships, updates in
            var membershipsRenewed = false
            
            for (membership, update) in zip(memberships, updates) {
                switch update {
                case .rejected(let error):
                    logger.error("Updating membership in group \(membership.groupId) with new certificates failed: \(error)")
                    self.tracker.log(action: TrackerAction.error, category: TrackerCategory.membershipRenewal, detail: String(describing: error))
                case .fulfilled:
                    logger.info("Renewed membership in group \(membership.groupId) successfully.")
                    membershipsRenewed = true
                }
            }
            
            if membershipsRenewed {
                self.tracker.log(action: .certificateRenewal, category: TrackerCategory.membershipRenewal)
            }
        }
    }
    
    func retry() {
        // nop, because should never happen.
    }
}
