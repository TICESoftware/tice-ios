//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import XCTest
import TICEAPIModels
import Shouter
import PromiseKit
import Cuckoo

@testable import TICE

class GroupManagerTests: XCTestCase {

    var signedInUser: SignedInUser!
    var groupStorageManager: MockGroupStorageManagerType!
    var cryptoManager: MockCryptoManagerType!
    var authManager: MockAuthManagerType!
    var backend: MockTICEAPI!
    var mailbox: MockMailboxType!
    var encoder: JSONEncoder!

    var groupManager: GroupManager!

    var team: Team!

    override func setUp() {
        super.setUp()

        signedInUser = SignedInUser(userId: UserId(), privateSigningKey: Data(), publicSigningKey: Data(), publicName: nil)
        groupStorageManager = MockGroupStorageManagerType()
        cryptoManager = MockCryptoManagerType()
        authManager = MockAuthManagerType()
        backend = MockTICEAPI()
        mailbox = MockMailboxType()
        encoder = JSONEncoder()

        groupManager = GroupManager(signedInUser: signedInUser, groupStorageManager: groupStorageManager, cryptoManager: cryptoManager, authManager: authManager, backend: backend, mailbox: mailbox, encoder: encoder)

        team = Team(groupId: GroupId(), groupKey: "groupKey".data, owner: signedInUser.userId, joinMode: .open, permissionMode: .everyone, tag: "groupTag", url: URL(string: "https://develop.tice.app/group/1")!, name: "team", meetupId: nil)
    }

    func testAddUserMember() throws {
        let completion = expectation(description: "Completion")

        let selfSignedCertificate = "selfSignedCertificate"
        let serverSignedCertificate = "serverSignedCertificate"

        let membership = Membership(userId: signedInUser.userId, publicSigningKey: signedInUser.publicSigningKey, groupId: team.groupId, admin: true, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedMembershipCertificate: serverSignedCertificate)
        let membershipData = try encoder.encode(membership)
        let encryptedMembership = "encryptedMembership".data

        let tokenKey = "tokenKey".data
        stub(cryptoManager) { stub in
            when(stub.encrypt(membershipData, secretKey: team.groupKey)).thenReturn(encryptedMembership)
            when(stub.tokenKeyForGroup(groupKey: team.groupKey, user: any())).thenReturn(tokenKey)
        }
        
        stub(authManager) { stub in
            when(stub.createUserSignedMembershipCertificate(userId: signedInUser.userId, groupId: any(), admin: true, issuerUserId: signedInUser.userId, signingKey: signedInUser.privateSigningKey)).thenReturn(selfSignedCertificate)
        }

        stub(groupStorageManager) { stub in
            when(stub.loadMemberships(groupId: team.groupId)).thenReturn([membership])
        }

        let updatedEtagResponse = UpdatedEtagResponse(groupTag: "updatedGroupTag")
        stub(backend) { stub in
            when(stub.addGroupMember(groupId: team.groupId, userId: signedInUser.userId, encryptedMembership: encryptedMembership, serverSignedMembershipCertificate: serverSignedCertificate, newTokenKey: tokenKey, groupTag: team.tag, notificationRecipients: [] as [NotificationRecipient])).thenReturn(Promise.value(updatedEtagResponse))
        }

        firstly {
            groupManager.addUserMember(into: team, admin: true, serverSignedMembershipCertificate: serverSignedCertificate)
        }.done { resultMembership, groupTag in
            XCTAssertEqual(resultMembership, membership, "Invalid membership")
            XCTAssertEqual(groupTag,  updatedEtagResponse.groupTag, "Invalid tag")
        }.catch { error in
            XCTFail(String(describing: error))
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testLeaveGroup() {
        let completion = expectation(description: "Completion")

        let selfSignedCertificate = "selfSignedCertificate"
        let serverSignedCertificate = "serverSignedCertificate"

        let membership = Membership(userId: signedInUser.userId, publicSigningKey: signedInUser.publicSigningKey, groupId: team.groupId, admin: false, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedMembershipCertificate: serverSignedCertificate)

        let tokenKey = "tokenKey".data
        stub(cryptoManager) { stub in
            when(stub.tokenKeyForGroup(groupKey: team.groupKey, user: any())).thenReturn(tokenKey)
        }

        stub(groupStorageManager) { stub in
            when(stub.loadMemberships(groupId: team.groupId)).thenReturn([membership])
            when(stub.loadMembership(userId: signedInUser.userId, groupId: team.groupId)).thenReturn(membership)
        }

        let updatedEtagResponse = UpdatedEtagResponse(groupTag: "updatedGroupTag")
        stub(backend) { stub in
            when(stub.deleteGroupMember(groupId: team.groupId, userId: signedInUser.userId, userServerSignedMembershipCertificate: serverSignedCertificate, ownServerSignedMembershipCertificate: serverSignedCertificate, tokenKey: tokenKey, groupTag: team.tag, notificationRecipients: [] as [NotificationRecipient])).thenReturn(Promise.value(updatedEtagResponse))
        }

        firstly {
            groupManager.leave(team)
        }.done { groupTag in
            XCTAssertEqual(groupTag, updatedEtagResponse.groupTag, "Invalid tag")
        }.catch { error in
            XCTFail(String(describing: error))
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testLeaveGroupAdmin() {
        let completion = expectation(description: "Completion")

        let selfSignedCertificate = "selfSignedCertificate"
        let serverSignedCertificate = "serverSignedCertificate"

        let membership = Membership(userId: signedInUser.userId, publicSigningKey: signedInUser.publicSigningKey, groupId: team.groupId, admin: true, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedMembershipCertificate: serverSignedCertificate)

        stub(groupStorageManager) { stub in
            when(stub.loadMembership(userId: signedInUser.userId, groupId: team.groupId)).thenReturn(membership)
        }

        firstly {
            groupManager.leave(team)
        }.done { groupTag in
            XCTFail("Leaving group should not have succeeded.")
        }.catch { error in
            guard case GroupManagerError.lastAdmin = error else {
                XCTFail(String(describing: error))
                return
            }
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testDeleteGroupMember() {
        let completion = expectation(description: "Completion")

        let ownAdminMembership = Membership(userId: signedInUser.userId, publicSigningKey: signedInUser.publicSigningKey, groupId: team.groupId, admin: true, selfSignedMembershipCertificate: "selfSignedCertificate", serverSignedMembershipCertificate: "serverSignedCertificate")
        let membershipToDelete = Membership(userId: UserId(), publicSigningKey: Data(), groupId: team.groupId, admin: false, selfSignedMembershipCertificate: "membershipToDeleteSelfSignedCertificate", serverSignedMembershipCertificate: "membershipToDeleteServerSignedMembershipCertificate")

        let tokenKey = "tokenKey".data
        stub(cryptoManager) { stub in
            when(stub.tokenKeyForGroup(groupKey: team.groupKey, user: any())).thenReturn(tokenKey)
        }

        let user = User(userId: membershipToDelete.userId, publicSigningKey: membershipToDelete.publicSigningKey, publicName: nil)
        let updatedGroupTag = "updatedGroupTag"
        stub(groupStorageManager) { stub in
            when(stub.loadMemberships(groupId: team.groupId)).thenReturn([ownAdminMembership, membershipToDelete])
            when(stub.loadMembership(userId: signedInUser.userId, groupId: team.groupId)).thenReturn(ownAdminMembership)
            when(stub.user(for: membershipToDelete)).thenReturn(user)
            when(stub.removeMembership(userId: membershipToDelete.userId, groupId: team.groupId, updatedGroupTag: updatedGroupTag)).thenDoNothing()
        }

        let updatedEtagResponse = UpdatedEtagResponse(groupTag: updatedGroupTag)
        let notificationRecipient = NotificationRecipient(userId: membershipToDelete.userId, serverSignedMembershipCertificate: membershipToDelete.serverSignedMembershipCertificate, priority: .alert)
        stub(backend) { stub in
            when(stub.deleteGroupMember(groupId: team.groupId, userId: membershipToDelete.userId, userServerSignedMembershipCertificate: membershipToDelete.serverSignedMembershipCertificate, ownServerSignedMembershipCertificate: ownAdminMembership.serverSignedMembershipCertificate, tokenKey: tokenKey, groupTag: team.tag, notificationRecipients: [notificationRecipient])).thenReturn(Promise.value(updatedEtagResponse))
        }

        firstly {
            groupManager.deleteGroupMember(membershipToDelete, from: team, serverSignedMembershipCertificate: ownAdminMembership.serverSignedMembershipCertificate)
        }.done {
            verify(self.backend).deleteGroupMember(groupId: self.team.groupId, userId: membershipToDelete.userId, userServerSignedMembershipCertificate: membershipToDelete.serverSignedMembershipCertificate, ownServerSignedMembershipCertificate: ownAdminMembership.serverSignedMembershipCertificate, tokenKey: tokenKey, groupTag: self.team.tag, notificationRecipients: [notificationRecipient])
        }.catch { error in
            XCTFail(String(describing: error))
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testNotificationRecipients() throws {
        let selfSignedCertificate = "selfSignedCertificate"
        let serverSignedCertificate = "serverSignedCertificate"

        let membership = Membership(userId: signedInUser.userId, publicSigningKey: signedInUser.publicSigningKey, groupId: team.groupId, admin: true, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedMembershipCertificate: serverSignedCertificate)
        let otherMembership = Membership(userId: UserId(), publicSigningKey: Data(), groupId: team.groupId, admin: false, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedMembershipCertificate: serverSignedCertificate)

        stub(groupStorageManager) { stub in
            when(stub.loadMemberships(groupId: team.groupId)).thenReturn([membership, otherMembership])
        }

        let notificationRecipients = try groupManager.notificationRecipients(groupId: team.groupId, alert: true)

        XCTAssertEqual(notificationRecipients.count, 1, "Invalid notification recipients")
        XCTAssertEqual(notificationRecipients.first?.userId, otherMembership.userId, "Invalid notification recipients")
        XCTAssertEqual(notificationRecipients.first?.serverSignedMembershipCertificate, otherMembership.serverSignedMembershipCertificate, "Invalid notification recipients")
        XCTAssertEqual(notificationRecipients.first?.priority, .alert, "Invalid notification recipients")
    }

    func testSendGroupMessage() {
        let completion = expectation(description: "Completion")

        let selfSignedCertificate = "selfSignedCertificate"
        let serverSignedCertificate = "serverSignedCertificate"

        let membership = Membership(userId: signedInUser.userId, publicSigningKey: signedInUser.publicSigningKey, groupId: team.groupId, admin: true, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedMembershipCertificate: serverSignedCertificate)
        let otherMembership = Membership(userId: UserId(), publicSigningKey: Data(), groupId: team.groupId, admin: false, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedMembershipCertificate: serverSignedCertificate)

        let user = User(userId: otherMembership.userId, publicSigningKey: otherMembership.publicSigningKey, publicName: nil)
        stub(groupStorageManager) { stub in
            when(stub.loadMemberships(groupId: team.groupId)).thenReturn([membership, otherMembership])
            when(stub.loadMembership(userId: signedInUser.userId, groupId: team.groupId)).thenReturn(membership)
            when(stub.user(for: otherMembership)).thenReturn(user)
        }

        let payloadContainer = PayloadContainer(payloadType: .groupUpdateV1, payload: GroupUpdate(groupId: team.groupId, action: .memberAdded))
        let collapseId = "collapseId"
        let priority = MessagePriority.alert
        stub(mailbox) { stub in
            when(stub.send(payloadContainer: payloadContainer, to: [otherMembership], serverSignedMembershipCertificate: serverSignedCertificate, priority: priority, collapseId: collapseId)).thenReturn(Promise())
        }

        firstly {
            groupManager.send(payloadContainer: payloadContainer, to: team, collapseId: collapseId, priority: priority)
        }.done { groupTag in
            verify(self.mailbox).send(payloadContainer: payloadContainer, to: [otherMembership], serverSignedMembershipCertificate: serverSignedCertificate, priority: priority, collapseId: collapseId)
        }.catch { error in
            XCTFail(String(describing: error))
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }

    func testSendGroupUpdateNotification() {
        let completion = expectation(description: "Completion")

        let selfSignedCertificate = "selfSignedCertificate"
        let serverSignedCertificate = "serverSignedCertificate"

        let membership = Membership(userId: signedInUser.userId, publicSigningKey: signedInUser.publicSigningKey, groupId: team.groupId, admin: true, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedMembershipCertificate: serverSignedCertificate)
        let otherMembership = Membership(userId: UserId(), publicSigningKey: Data(), groupId: team.groupId, admin: false, selfSignedMembershipCertificate: selfSignedCertificate, serverSignedMembershipCertificate: serverSignedCertificate)

        let user = User(userId: otherMembership.userId, publicSigningKey: otherMembership.publicSigningKey, publicName: nil)
        stub(groupStorageManager) { stub in
            when(stub.loadMemberships(groupId: team.groupId)).thenReturn([membership, otherMembership])
            when(stub.loadMembership(userId: signedInUser.userId, groupId: team.groupId)).thenReturn(membership)
            when(stub.user(for: otherMembership)).thenReturn(user)
        }

        let payloadContainer = PayloadContainer(payloadType: .groupUpdateV1, payload: GroupUpdate(groupId: team.groupId, action: .memberAdded))
        stub(mailbox) { stub in
            when(stub.send(payloadContainer: payloadContainer, to: [otherMembership], serverSignedMembershipCertificate: serverSignedCertificate, priority: MessagePriority.alert, collapseId: nil as Envelope.CollapseIdentifier?)).thenReturn(Promise())
        }

        firstly {
            groupManager.sendGroupUpdateNotification(to: team, action: .memberAdded)
        }.done { groupTag in
            verify(self.mailbox).send(payloadContainer: payloadContainer, to: [otherMembership], serverSignedMembershipCertificate: serverSignedCertificate, priority: MessagePriority.alert, collapseId: nil as Envelope.CollapseIdentifier?)
        }.catch { error in
            XCTFail(String(describing: error))
        }.finally {
            completion.fulfill()
        }

        wait(for: [completion])
    }
}
