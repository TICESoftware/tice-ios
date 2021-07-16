//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import XCTest
import Cuckoo
import TICEAPIModels
import PromiseKit

@testable import TICE

enum MembershipCertificateRenewealViewModelTestError: Error {
    case error
}

class MembershipCertificateRenewalViewModelTests: XCTestCase {

    var groupStorageManager: MockGroupStorageManagerType!
    var signedInUserManager: MockSignedInUserManagerType!
    var cryptoManager: MockCryptoManagerType!
    var authManager: MockAuthManagerType!
    var backend: MockTICEAPI!
    var coordinator: MockAppFlow!
    var encoder: JSONEncoder!
    var certificateValidityTimeRenewalThreshold: TimeInterval!
    var tracker: TrackerType!
    
    var signedInUser: SignedInUser!
    
    var viewModel: MembershipCertificateRenewalViewModel!

    override func setUp() {
        super.setUp()

        groupStorageManager = MockGroupStorageManagerType()
        signedInUserManager = MockSignedInUserManagerType()
        cryptoManager = MockCryptoManagerType()
        authManager = MockAuthManagerType()
        backend = MockTICEAPI()
        coordinator = MockAppFlow()
        encoder = JSONEncoder()
        certificateValidityTimeRenewalThreshold = 10.0
        tracker = MockTracker()
        
        viewModel = MembershipCertificateRenewalViewModel(groupStorageManager: groupStorageManager, signedInUserManager: signedInUserManager, cryptoManager: cryptoManager, authManager: authManager, backend: backend, coordinator: coordinator, encoder: encoder, certificateValidityTimeRenewalThreshold: certificateValidityTimeRenewalThreshold, tracker: tracker)
        
        signedInUser = SignedInUser(userId: UserId(), privateSigningKey: Data(), publicSigningKey: Data(), publicName: nil)
    }

    func testNoSignedInUser() throws {
        stub(signedInUserManager) { stub in
            when(stub.signedInUser.get).thenReturn(nil)
        }
        
        stub(coordinator) { stub in
            when(stub.finishHousekeeping()).thenDoNothing()
        }
        
        viewModel.enter()
        
        verify(coordinator).finishHousekeeping()
    }
    
    func testNoCertificatesToRenew() throws {
        stub(signedInUserManager) { stub in
            when(stub.signedInUser.get).thenReturn(signedInUser)
        }
        
        let exp = expectation(description: "Completion")
        
        stub(coordinator) { stub in
            when(stub.finishHousekeeping()).then { exp.fulfill() }
        }
        
        let membership = Membership(userId: signedInUser.userId, publicSigningKey: signedInUser.publicSigningKey, groupId: GroupId(), admin: false, selfSignedMembershipCertificate: "selfSigned", serverSignedMembershipCertificate: "serverSigned")
        
        stub(groupStorageManager) { stub in
            when(stub.loadMemberships(userId: signedInUser.userId)).thenReturn([membership])
        }
        
        stub(authManager) { stub in
            when(stub.membershipCertificateExpirationDate(certificate: membership.selfSignedMembershipCertificate!)).thenReturn(Date().addingTimeInterval(certificateValidityTimeRenewalThreshold + 10.0))
            when(stub.membershipCertificateExpirationDate(certificate: membership.serverSignedMembershipCertificate)).thenReturn(Date().addingTimeInterval( certificateValidityTimeRenewalThreshold + 10))
        }
        
        viewModel.enter()
        
        wait(for: [exp])
    }
    
    func testSelfSignedCertificatesNeedsRenewal() throws {
        stub(signedInUserManager) { stub in
            when(stub.signedInUser.get).thenReturn(signedInUser)
        }
        
        let exp = expectation(description: "Completion")
        
        stub(coordinator) { stub in
            when(stub.finishHousekeeping()).then { exp.fulfill() }
        }
        
        let membership = Membership(userId: signedInUser.userId, publicSigningKey: signedInUser.publicSigningKey, groupId: GroupId(), admin: false, selfSignedMembershipCertificate: "selfSigned", serverSignedMembershipCertificate: "serverSigned")
        let team = Team(groupId: membership.groupId, groupKey: "groupKey".data, owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "tag1", url: URL(string: "https://example.com")!, name: nil, meetupId: nil)
        
        let renewedServerSignedCertificate = "renewedServerSigned"
        let renewCertificateResponse = RenewCertificateResponse(certificate: renewedServerSignedCertificate)
        
        let renewedSelfSignedCertificate = "renewedSelfSigned"
        let renewedMembership = Membership(userId: membership.userId, publicSigningKey: membership.publicSigningKey, groupId: membership.groupId, admin: membership.admin, selfSignedMembershipCertificate: renewedSelfSignedCertificate, serverSignedMembershipCertificate: renewedServerSignedCertificate)
        let encryptedMembership = "encryptedMembership".data
        let tokenKey = "tokenKey".data
        
        let otherMembership = Membership(userId: UserId(), publicSigningKey: Data(), groupId: team.groupId, admin: true, serverSignedMembershipCertificate: "otherServerSigned")
        let notificationRecipient = NotificationRecipient(userId: otherMembership.userId, serverSignedMembershipCertificate: otherMembership.serverSignedMembershipCertificate, priority: .background)
        
        let updatedETagResponse = UpdatedEtagResponse(groupTag: "tag2")
        
        stub(groupStorageManager) { stub in
            when(stub.loadMemberships(userId: signedInUser.userId)).thenReturn([membership])
            when(stub.loadGroup(groupId: team.groupId)).thenReturn(team)
            when(stub.updateGroupTag(groupId: membership.groupId, tag: updatedETagResponse.groupTag)).thenDoNothing()
            when(stub.loadMemberships(groupId: team.groupId)).thenReturn([otherMembership])
            when(stub.store(any())).thenDoNothing()
        }
        
        stub(backend) { stub in
            when(stub.renewCertificate(membership.serverSignedMembershipCertificate)).thenReturn(Promise.value(renewCertificateResponse))
            when(stub.updateGroupMember(groupId: membership.groupId, userId: signedInUser.userId, encryptedMembership: encryptedMembership, serverSignedMembershipCertificate: renewedServerSignedCertificate, tokenKey: tokenKey, groupTag: team.tag, notificationRecipients: [notificationRecipient])).thenReturn(Promise.value(updatedETagResponse))
        }
        
        stub(authManager) { stub in
            when(stub.membershipCertificateExpirationDate(certificate: membership.selfSignedMembershipCertificate!)).thenReturn(Date().addingTimeInterval(certificateValidityTimeRenewalThreshold - 10))
            when(stub.membershipCertificateExpirationDate(certificate: membership.serverSignedMembershipCertificate)).thenReturn(Date().addingTimeInterval(certificateValidityTimeRenewalThreshold + 10))
            when(stub.createUserSignedMembershipCertificate(userId: signedInUser.userId, groupId: membership.groupId, admin: membership.admin, issuerUserId: signedInUser.userId, signingKey: signedInUser.privateSigningKey)).thenReturn(renewedSelfSignedCertificate)
        }
        
        stub(cryptoManager) { stub in
            when(stub.encrypt(try! encoder.encode(renewedMembership), secretKey: team.groupKey)).thenReturn(encryptedMembership)
            when(stub.tokenKeyForGroup(groupKey: team.groupKey, user: any())).thenReturn(tokenKey)
        }
        
        viewModel.enter()
        
        wait(for: [exp])
        
        verify(groupStorageManager).store(renewedMembership)
    }
    
    func testServerSignedCertificatesNeedsRenewal() throws {
        stub(signedInUserManager) { stub in
            when(stub.signedInUser.get).thenReturn(signedInUser)
        }
        
        let exp = expectation(description: "Completion")
        
        stub(coordinator) { stub in
            when(stub.finishHousekeeping()).then { exp.fulfill() }
        }
        
        let membership = Membership(userId: signedInUser.userId, publicSigningKey: signedInUser.publicSigningKey, groupId: GroupId(), admin: false, selfSignedMembershipCertificate: "selfSigned", serverSignedMembershipCertificate: "serverSigned")
        let team = Team(groupId: membership.groupId, groupKey: "groupKey".data, owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "tag1", url: URL(string: "https://example.com")!, name: nil, meetupId: nil)
        
        let renewedServerSignedCertificate = "renewedServerSigned"
        let renewCertificateResponse = RenewCertificateResponse(certificate: renewedServerSignedCertificate)
        
        let renewedSelfSignedCertificate = "renewedSelfSigned"
        let renewedMembership = Membership(userId: membership.userId, publicSigningKey: membership.publicSigningKey, groupId: membership.groupId, admin: membership.admin, selfSignedMembershipCertificate: renewedSelfSignedCertificate, serverSignedMembershipCertificate: renewedServerSignedCertificate)
        let encryptedMembership = "encryptedMembership".data
        let tokenKey = "tokenKey".data
        
        let otherMembership = Membership(userId: UserId(), publicSigningKey: Data(), groupId: team.groupId, admin: true, serverSignedMembershipCertificate: "otherServerSigned")
        let notificationRecipient = NotificationRecipient(userId: otherMembership.userId, serverSignedMembershipCertificate: otherMembership.serverSignedMembershipCertificate, priority: .background)
        
        let updatedETagResponse = UpdatedEtagResponse(groupTag: "tag2")
        
        stub(groupStorageManager) { stub in
            when(stub.loadMemberships(userId: signedInUser.userId)).thenReturn([membership])
            when(stub.loadGroup(groupId: team.groupId)).thenReturn(team)
            when(stub.updateGroupTag(groupId: membership.groupId, tag: updatedETagResponse.groupTag)).thenDoNothing()
            when(stub.loadMemberships(groupId: team.groupId)).thenReturn([otherMembership])
            when(stub.store(any())).thenDoNothing()
        }
        
        stub(backend) { stub in
            when(stub.renewCertificate(membership.serverSignedMembershipCertificate)).thenReturn(Promise.value(renewCertificateResponse))
            when(stub.updateGroupMember(groupId: membership.groupId, userId: signedInUser.userId, encryptedMembership: encryptedMembership, serverSignedMembershipCertificate: renewedServerSignedCertificate, tokenKey: tokenKey, groupTag: team.tag, notificationRecipients: [notificationRecipient])).thenReturn(Promise.value(updatedETagResponse))
        }
        
        stub(authManager) { stub in
            when(stub.membershipCertificateExpirationDate(certificate: membership.selfSignedMembershipCertificate!)).thenReturn(Date().addingTimeInterval(certificateValidityTimeRenewalThreshold + 10))
            when(stub.membershipCertificateExpirationDate(certificate: membership.serverSignedMembershipCertificate)).thenReturn(Date().addingTimeInterval(certificateValidityTimeRenewalThreshold - 10))
            when(stub.createUserSignedMembershipCertificate(userId: signedInUser.userId, groupId: membership.groupId, admin: membership.admin, issuerUserId: signedInUser.userId, signingKey: signedInUser.privateSigningKey)).thenReturn(renewedSelfSignedCertificate)
        }
        
        stub(cryptoManager) { stub in
            when(stub.encrypt(try! encoder.encode(renewedMembership), secretKey: team.groupKey)).thenReturn(encryptedMembership)
            when(stub.tokenKeyForGroup(groupKey: team.groupKey, user: any())).thenReturn(tokenKey)
        }
        
        viewModel.enter()
        
        wait(for: [exp])
        
        verify(groupStorageManager).store(renewedMembership)
    }
    
    func testInvalidOldCertificate() throws {
        stub(signedInUserManager) { stub in
            when(stub.signedInUser.get).thenReturn(signedInUser)
        }
        
        let exp = expectation(description: "Completion")
        
        stub(coordinator) { stub in
            when(stub.finishHousekeeping()).then { exp.fulfill() }
        }
        
        let validMembership = Membership(userId: signedInUser.userId, publicSigningKey: signedInUser.publicSigningKey, groupId: GroupId(), admin: false, selfSignedMembershipCertificate: "selfSignedValid", serverSignedMembershipCertificate: "serverSignedValid")
        let invalidMembership = Membership(userId: signedInUser.userId, publicSigningKey: signedInUser.publicSigningKey, groupId: GroupId(), admin: false, selfSignedMembershipCertificate: "selfSignedInvalid", serverSignedMembershipCertificate: "serverSignedInvalid")
        let team = Team(groupId: validMembership.groupId, groupKey: "groupKey".data, owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "tag1", url: URL(string: "https://example.com")!, name: nil, meetupId: nil)
        
        let renewedServerSignedCertificate = "renewedServerSigned"
        let renewCertificateResponse = RenewCertificateResponse(certificate: renewedServerSignedCertificate)
        
        let renewedSelfSignedCertificate = "renewedSelfSigned"
        let renewedMembership = Membership(userId: validMembership.userId, publicSigningKey: validMembership.publicSigningKey, groupId: validMembership.groupId, admin: validMembership.admin, selfSignedMembershipCertificate: renewedSelfSignedCertificate, serverSignedMembershipCertificate: renewedServerSignedCertificate)
        let encryptedMembership = "encryptedMembership".data
        let tokenKey = "tokenKey".data
        
        let otherMembership = Membership(userId: UserId(), publicSigningKey: Data(), groupId: team.groupId, admin: true, serverSignedMembershipCertificate: "otherServerSigned")
        let notificationRecipient = NotificationRecipient(userId: otherMembership.userId, serverSignedMembershipCertificate: otherMembership.serverSignedMembershipCertificate, priority: .background)
        
        let updatedETagResponse = UpdatedEtagResponse(groupTag: "tag2")
        
        stub(groupStorageManager) { stub in
            when(stub.loadMemberships(userId: signedInUser.userId)).thenReturn([invalidMembership, validMembership])
            when(stub.loadGroup(groupId: team.groupId)).thenReturn(team)
            when(stub.updateGroupTag(groupId: validMembership.groupId, tag: updatedETagResponse.groupTag)).thenDoNothing()
            when(stub.loadMemberships(groupId: team.groupId)).thenReturn([otherMembership])
            when(stub.store(any())).thenDoNothing()
        }
        
        stub(backend) { stub in
            when(stub.renewCertificate(validMembership.serverSignedMembershipCertificate)).thenReturn(Promise.value(renewCertificateResponse))
            when(stub.updateGroupMember(groupId: validMembership.groupId, userId: signedInUser.userId, encryptedMembership: encryptedMembership, serverSignedMembershipCertificate: renewedServerSignedCertificate, tokenKey: tokenKey, groupTag: team.tag, notificationRecipients: [notificationRecipient])).thenReturn(Promise.value(updatedETagResponse))
        }
        
        stub(authManager) { stub in
            when(stub.membershipCertificateExpirationDate(certificate: invalidMembership.selfSignedMembershipCertificate!)).thenThrow(MembershipCertificateRenewealViewModelTestError.error)
            when(stub.membershipCertificateExpirationDate(certificate: validMembership.selfSignedMembershipCertificate!)).thenReturn(Date().addingTimeInterval(certificateValidityTimeRenewalThreshold + 10))
            when(stub.membershipCertificateExpirationDate(certificate: validMembership.serverSignedMembershipCertificate)).thenReturn(Date().addingTimeInterval(certificateValidityTimeRenewalThreshold - 10))
            when(stub.createUserSignedMembershipCertificate(userId: signedInUser.userId, groupId: validMembership.groupId, admin: validMembership.admin, issuerUserId: signedInUser.userId, signingKey: signedInUser.privateSigningKey)).thenReturn(renewedSelfSignedCertificate)
        }
        
        stub(cryptoManager) { stub in
            when(stub.encrypt(try! encoder.encode(renewedMembership), secretKey: team.groupKey)).thenReturn(encryptedMembership)
            when(stub.tokenKeyForGroup(groupKey: team.groupKey, user: any())).thenReturn(tokenKey)
        }
        
        viewModel.enter()
        
        wait(for: [exp])
        
        verify(backend).renewCertificate(any())
        verify(groupStorageManager).store(renewedMembership)
        verify(groupStorageManager).updateGroupTag(groupId: any(), tag: any())
    }
    
    func testRenewalFails() throws {
        stub(signedInUserManager) { stub in
            when(stub.signedInUser.get).thenReturn(signedInUser)
        }
        
        let exp = expectation(description: "Completion")
        
        stub(coordinator) { stub in
            when(stub.finishHousekeeping()).then { exp.fulfill() }
        }
        
        let validMembership = Membership(userId: signedInUser.userId, publicSigningKey: signedInUser.publicSigningKey, groupId: GroupId(), admin: false, selfSignedMembershipCertificate: "selfSignedValid", serverSignedMembershipCertificate: "serverSignedValid")
        let invalidMembership = Membership(userId: signedInUser.userId, publicSigningKey: signedInUser.publicSigningKey, groupId: GroupId(), admin: false, selfSignedMembershipCertificate: "selfSignedInvalid", serverSignedMembershipCertificate: "serverSignedInvalid")
        let team = Team(groupId: validMembership.groupId, groupKey: "groupKey".data, owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "tag1", url: URL(string: "https://example.com")!, name: nil, meetupId: nil)
        
        let renewedServerSignedCertificate = "renewedServerSigned"
        let renewCertificateResponse = RenewCertificateResponse(certificate: renewedServerSignedCertificate)
        
        let renewedSelfSignedCertificate = "renewedSelfSigned"
        let renewedMembership = Membership(userId: validMembership.userId, publicSigningKey: validMembership.publicSigningKey, groupId: validMembership.groupId, admin: validMembership.admin, selfSignedMembershipCertificate: renewedSelfSignedCertificate, serverSignedMembershipCertificate: renewedServerSignedCertificate)
        let encryptedMembership = "encryptedMembership".data
        let tokenKey = "tokenKey".data
        
        let otherMembership = Membership(userId: UserId(), publicSigningKey: Data(), groupId: team.groupId, admin: true, serverSignedMembershipCertificate: "otherServerSigned")
        let notificationRecipient = NotificationRecipient(userId: otherMembership.userId, serverSignedMembershipCertificate: otherMembership.serverSignedMembershipCertificate, priority: .background)
        
        let updatedETagResponse = UpdatedEtagResponse(groupTag: "tag2")
        
        stub(groupStorageManager) { stub in
            when(stub.loadMemberships(userId: signedInUser.userId)).thenReturn([invalidMembership, validMembership])
            when(stub.loadGroup(groupId: team.groupId)).thenReturn(team)
            when(stub.updateGroupTag(groupId: validMembership.groupId, tag: updatedETagResponse.groupTag)).thenDoNothing()
            when(stub.loadMemberships(groupId: team.groupId)).thenReturn([otherMembership])
            when(stub.store(renewedMembership)).thenDoNothing()
        }
        
        stub(backend) { stub in
            when(stub.renewCertificate(validMembership.serverSignedMembershipCertificate)).thenReturn(Promise.value(renewCertificateResponse))
            when(stub.updateGroupMember(groupId: validMembership.groupId, userId: signedInUser.userId, encryptedMembership: encryptedMembership, serverSignedMembershipCertificate: renewedServerSignedCertificate, tokenKey: tokenKey, groupTag: team.tag, notificationRecipients: [notificationRecipient])).thenReturn(Promise.value(updatedETagResponse))
        }
        
        stub(authManager) { stub in
            when(stub.membershipCertificateExpirationDate(certificate: any())).thenReturn(Date().addingTimeInterval(certificateValidityTimeRenewalThreshold - 10))
            when(stub.createUserSignedMembershipCertificate(userId: signedInUser.userId, groupId: invalidMembership.groupId, admin: invalidMembership.admin, issuerUserId: signedInUser.userId, signingKey: signedInUser.privateSigningKey)).thenThrow(MembershipCertificateRenewealViewModelTestError.error)
            when(stub.createUserSignedMembershipCertificate(userId: signedInUser.userId, groupId: validMembership.groupId, admin: validMembership.admin, issuerUserId: signedInUser.userId, signingKey: signedInUser.privateSigningKey)).thenReturn(renewedSelfSignedCertificate)
        }
        
        stub(cryptoManager) { stub in
            when(stub.encrypt(try! encoder.encode(renewedMembership), secretKey: team.groupKey)).thenReturn(encryptedMembership)
            when(stub.tokenKeyForGroup(groupKey: team.groupKey, user: any())).thenReturn(tokenKey)
        }
        
        viewModel.enter()
        
        wait(for: [exp])
        
        verify(backend).renewCertificate(any())
        verify(groupStorageManager).updateGroupTag(groupId: validMembership.groupId, tag: updatedETagResponse.groupTag)
        verify(groupStorageManager).store(renewedMembership)
        verify(groupStorageManager, never()).updateGroupTag(groupId: invalidMembership.groupId, tag: any())
        verify(groupStorageManager, never()).store(not(equal(to: renewedMembership)))
    }
}
