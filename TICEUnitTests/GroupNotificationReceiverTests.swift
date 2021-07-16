//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import XCTest
import TICEAPIModels
import CoreLocation
import PromiseKit
import Swinject
import Shouter
import Cuckoo

@testable import TICE

class GroupNotificationReceiverTests: XCTestCase {
    var postOffice: MockPostOfficeType!
    var notificationManager: MockNotificationManagerType!
    var teamManager: MockTeamManagerType!
    var meetupManager: MockMeetupManagerType!
    var locationManager: MockLocationManagerType!
    var groupStorageManager: MockGroupStorageManagerType!
    var locationStorageManager: MockLocationStorageManagerType!
    var userManager: MockUserManagerType!
    var nameSupplier: MockNameSupplierType!
    var chatManager: MockChatManagerType!
    var deepLinkParser: MockDeepLinkParserType!
    var messageSender: MockMessageSenderType!
    var mailbox: MockMailboxType!
    var locationSharingManager: MockLocationSharingManagerType!

    var sender: User!
    var team: Team!
    var meetup: Meetup!
    var signedInUser: SignedInUser!
    
    var groupNotificationReceiver: GroupNotificationReceiver!
    
    override func setUp() {
        super.setUp()
        
        postOffice = MockPostOfficeType()
        notificationManager = MockNotificationManagerType()
        teamManager = MockTeamManagerType()
        meetupManager = MockMeetupManagerType()
        locationManager = MockLocationManagerType()
        groupStorageManager = MockGroupStorageManagerType()
        locationStorageManager = MockLocationStorageManagerType()
        userManager = MockUserManagerType()
        nameSupplier = MockNameSupplierType()
        chatManager = MockChatManagerType()
        deepLinkParser = MockDeepLinkParserType()
        messageSender = MockMessageSenderType()
        mailbox = MockMailboxType()
		locationSharingManager = MockLocationSharingManagerType()
        
        sender = User(userId: UserId(), publicSigningKey: Data(), publicName: "senderName")
        team = Team(groupId: GroupId(), groupKey: "teamKey".data, owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "teamTag", url: URL(string: "https://develop.tice.app/group/1")!, name: "teamName", meetupId: nil)
        meetup = Meetup(groupId: GroupId(), groupKey: "meetupKey".data, owner: UserId(), joinMode: .open, permissionMode: .everyone, tag: "meetupTag", teamId: team.groupId, meetingPoint: nil, locationSharingEnabled: true)
        signedInUser = SignedInUser(userId: UUID(), privateSigningKey: Data(), publicSigningKey: Data(), publicName: nil)
        
        stub(nameSupplier) { stub in
            when(stub.name(user: any())).then { $0.publicName! }
            when(stub.name(team: any())).then { $0.name! }
        }
        
        groupNotificationReceiver = GroupNotificationReceiver(postOffice: postOffice, teamManager: teamManager, groupStorageManager: groupStorageManager, notificationManager: notificationManager, meetupManager: meetupManager, locationManager: locationManager, locationStorageManager: locationStorageManager, locationSharingManager: locationSharingManager, userManager: userManager, nameSupplier: nameSupplier, chatManager: chatManager, deepLinkParser: deepLinkParser, messageSender: messageSender, mailbox: mailbox, signedInUser: signedInUser)
    }
    
    func testRegistering() {
        stub(postOffice) { stub in
            when(stub.handlers.get).thenReturn([:])
            when(stub.handlers.set(any())).thenDoNothing()
        }
        
        stub(notificationManager) { stub in
            when(stub.handlers.get).thenReturn([:])
            when(stub.handlers.set(any())).thenDoNothing()
        }
        
        groupNotificationReceiver.registerHandler()
        
        verify(postOffice, times(2)).handlers.set(any())
        verify(notificationManager, times(2)).handlers.set(any())
    }
    
    func testTeamDeleted() {
        let payload = GroupUpdate(groupId: team.groupId, action: .groupDeleted)
        let metaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: sender.userId, timestamp: Date(), collapseId: nil, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, conversationInvitation: nil)
        
        stub(userManager) { stub in
            when(stub.user(sender.userId)).thenReturn(sender)
        }
        
        stub(groupStorageManager) { stub in
            when(stub.loadTeam(team.groupId)).thenReturn(team)
            when(stub.removeTeam(team.groupId)).thenDoNothing()
        }

        let notificationTitle = L10n.Notification.Group.Deleted.title
        let notificationBody = L10n.Notification.Group.Deleted.body(self.nameSupplier.name(user: self.sender), self.nameSupplier.name(team: self.team))
        stub(notificationManager) { stub in
            when(stub.triggerNotification(title: notificationTitle, body: notificationBody, state: any(), category: any(), userInfo: any())).thenDoNothing()
        }
        
        let completion = expectation(description: "Completion")
        groupNotificationReceiver.handleGroupUpdate(payload: payload, metaInfo: metaInfo) { result in
            XCTAssertEqual(result, .newData, "Invalid result")
            verify(self.groupStorageManager).removeTeam(self.team.groupId)
            
            completion.fulfill()
        }
        
        wait(for: [completion])
        
        verify(notificationManager).triggerNotification(title: notificationTitle, body: notificationBody, state: any(), category: any(), userInfo: any())
    }
    
    func testUserNotAvailable() {
        let payload = GroupUpdate(groupId: team.groupId, action: .groupDeleted)
        let metaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: sender.userId, timestamp: Date(), collapseId: nil, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, conversationInvitation: nil)
        
        stub(userManager) { stub in
            when(stub.user(sender.userId)).thenReturn(nil)
        }
        
        stub(groupStorageManager) { stub in
            when(stub.loadTeam(team.groupId)).thenReturn(team)
            when(stub.removeTeam(team.groupId)).thenDoNothing()
        }

        let notificationTitle = L10n.Notification.Group.Deleted.title
        let notificationBody = L10n.Notification.Group.Deleted.body(L10n.User.Name.someone, self.nameSupplier.name(team: self.team))
        stub(notificationManager) { stub in
            when(stub.triggerNotification(title: notificationTitle, body: notificationBody, state: any(), category: any(), userInfo: any())).thenDoNothing()
        }
        
        let completion = expectation(description: "Completion")
        groupNotificationReceiver.handleGroupUpdate(payload: payload, metaInfo: metaInfo) { result in
            XCTAssertEqual(result, .newData, "Invalid result")
            verify(self.groupStorageManager).removeTeam(self.team.groupId)
            completion.fulfill()
        }
        
        wait(for: [completion])
        
        verify(notificationManager).triggerNotification(title: notificationTitle, body: notificationBody, state: any(), category: any(), userInfo: any())
    }
    
    func testMeetupDeleted() {
        let payload = GroupUpdate(groupId: meetup.groupId, action: .groupDeleted)
        let metaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: sender.userId, timestamp: Date(), collapseId: nil, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, conversationInvitation: nil)
        
        stub(groupStorageManager) { stub in
            when(stub.loadTeam(meetup.groupId)).thenReturn(nil)
            when(stub.loadMeetup(meetup.groupId)).thenReturn(meetup)
            when(stub.removeMeetup(meetup: meetup)).thenDoNothing()
            when(stub.teamOf(meetup: any())).thenReturn(team)
        }
        
        stub(teamManager) { stub in
            when(stub.reload(team: any(), reloadMeetup: true)).thenReturn(Promise.value(team))
        }
        
        let completion = expectation(description: "Completion")
        groupNotificationReceiver.handleGroupUpdate(payload: payload, metaInfo: metaInfo) { result in
            XCTAssertEqual(result, .newData, "Invalid result")
            verify(self.groupStorageManager).removeMeetup(meetup: self.meetup)
            
            completion.fulfill()
        }
        
        wait(for: [completion])
    }
    
    func testTeamMemberAddedWhileNotSharingLocation() {
        let payload = GroupUpdate(groupId: team.groupId, action: .memberAdded)
        let metaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: sender.userId, timestamp: Date(), collapseId: nil, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, conversationInvitation: nil)
        
        stub(userManager) { stub in
            when(stub.getUser(sender.userId)).thenReturn(Promise.value(sender))
            when(stub.user(sender.userId)).thenReturn(sender)
        }
        
		let senderMembership = Membership(userId: sender.userId, publicSigningKey: PublicKey(), groupId: team.groupId, admin: false, serverSignedMembershipCertificate: "serverSignedMembershipCertificate")
        stub(groupStorageManager) { stub in
            when(stub.loadTeam(team.groupId)).thenReturn(team)
            when(stub.loadMembership(userId: sender.userId, groupId: team.groupId)).thenReturn(senderMembership)
        }
        stub(locationSharingManager) { stub in
            when(stub.locationSharingState(userId: signedInUser.userId, groupId: team.groupId)).thenReturn(LocationSharingState(userId: signedInUser.userId, groupId: team.groupId, enabled: false, lastUpdated: Date()))
        }
        
        let notificationTitle = L10n.Notification.Group.MemberAdded.title(self.nameSupplier.name(user: self.sender))
        let notificationBody = L10n.Notification.Group.MemberAdded.body(self.nameSupplier.name(user: self.sender), self.nameSupplier.name(team: self.team))
        stub(notificationManager) { stub in
            when(stub.triggerNotification(title: notificationTitle, body: notificationBody, state: any(), category: any(), userInfo: any())).thenDoNothing()
        }
        
        stub(teamManager) { stub in
            when(stub.reload(team: any(), reloadMeetup: true)).thenReturn(Promise.value(team))
        }
        
        stub(chatManager) { stub in
            when(stub.add(message: any(), to: team.groupId)).then { message, _ in
                guard let message = message as? MetaMessage else { XCTFail(); return }
                XCTAssertEqual(message.message, LocalizedFormattedString("chat_meta_group_memberAdded_body", self.sender.publicName!))
            }
        }
        
        let completion = expectation(description: "Completion")
        groupNotificationReceiver.handleGroupUpdate(payload: payload, metaInfo: metaInfo) { result in
            XCTAssertEqual(result, .newData, "Invalid result")
            completion.fulfill()
        }
        
        wait(for: [completion])
        
        verify(notificationManager).triggerNotification(title: notificationTitle, body: notificationBody, state: any(), category: any(), userInfo: any())
        verify(chatManager).add(message: any(), to: any())
    }
    
    func testTeamMemberAddedWhileSharingLocation() {
        let payload = GroupUpdate(groupId: team.groupId, action: .memberAdded)
        let metaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: sender.userId, timestamp: Date(), collapseId: nil, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, conversationInvitation: nil)
        
        stub(userManager) { stub in
            when(stub.getUser(sender.userId)).thenReturn(Promise.value(sender))
            when(stub.user(sender.userId)).thenReturn(sender)
            when(stub.user(signedInUser.userId)).thenReturn(signedInUser)
        }
        
        let senderMembership = Membership(userId: sender.userId, publicSigningKey: PublicKey(), groupId: team.groupId, admin: false, serverSignedMembershipCertificate: "serverSignedMembershipCertificate")
        let signedInUserMembership = Membership(userId: signedInUser.userId, publicSigningKey: PublicKey(), groupId: team.groupId, admin: true, serverSignedMembershipCertificate: "serverSignedMembershipCertificate")
        stub(groupStorageManager) { stub in
            when(stub.loadTeam(team.groupId)).thenReturn(team)
            when(stub.loadMembership(userId: sender.userId, groupId: team.groupId)).thenReturn(senderMembership)
            when(stub.loadMembership(userId: signedInUser.userId, groupId: team.groupId)).thenReturn(signedInUserMembership)
        }
        stub(locationManager) { stub in
            when(stub.lastUserLocation).get.thenReturn(Location(latitude: 12, longitude: 34))
        }
        stub(locationSharingManager) { stub in
            when(stub.locationSharingState(userId: signedInUser.userId, groupId: team.groupId)).thenReturn(LocationSharingState(userId: signedInUser.userId, groupId: team.groupId, enabled: true, lastUpdated: Date()))
        }
        stub(mailbox) { stub in
            when(stub).send(payloadContainer: any(), to: any(), serverSignedMembershipCertificate: any(), priority: any(), collapseId: any()).thenReturn(.value)
        }
        
        let notificationTitle = L10n.Notification.Group.MemberAdded.title(self.nameSupplier.name(user: self.sender))
        let notificationBody = L10n.Notification.Group.MemberAdded.body(self.nameSupplier.name(user: self.sender), self.nameSupplier.name(team: self.team))
        stub(notificationManager) { stub in
            when(stub.triggerNotification(title: notificationTitle, body: notificationBody, state: any(), category: any(), userInfo: any())).thenDoNothing()
        }
        
        stub(chatManager) { stub in
            when(stub.add(message: any(), to: team.groupId)).then { message, _ in
                guard let message = message as? MetaMessage else { XCTFail(); return }
                XCTAssertEqual(message.message, LocalizedFormattedString("chat_meta_group_memberAdded_body", self.sender.publicName!))
            }
        }
        
        stub(teamManager) { stub in
            when(stub.reload(team: any(), reloadMeetup: true)).thenReturn(Promise.value(team))
        }
        
        let completion = expectation(description: "Completion")
        groupNotificationReceiver.handleGroupUpdate(payload: payload, metaInfo: metaInfo) { result in
            XCTAssertEqual(result, .newData, "Invalid result")
            completion.fulfill()
        }
        
        wait(for: [completion])
        
        verify(mailbox, times(2)).send(payloadContainer: any(), to: [senderMembership], serverSignedMembershipCertificate: any(), priority: MessagePriority.deferred, collapseId: any())
    }

    func testMeetupMemberAdded() {
        let payload = GroupUpdate(groupId: meetup.groupId, action: .memberAdded)
        let metaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: sender.userId, timestamp: Date(), collapseId: nil, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, conversationInvitation: nil)
        
        stub(userManager) { stub in
            when(stub.getUser(sender.userId)).thenReturn(Promise.value(sender))
            when(stub.user(sender.userId)).thenReturn(sender)
        }
        
        stub(groupStorageManager) { stub in
            when(stub.loadTeam(meetup.groupId)).thenReturn(nil)
            when(stub.loadMeetup(meetup.groupId)).thenReturn(meetup)
            when(stub.teamOf(meetup: any())).thenReturn(team)
            when(stub.loadMembership(userId: sender.userId, groupId: meetup.groupId)).thenReturn(Membership(userId: sender.userId, publicSigningKey: Data(), groupId: meetup.groupId, admin: false, serverSignedMembershipCertificate: "serverSignedMembershipCertificate"))
            when(stub.loadMembership(userId: signedInUser.userId, groupId: meetup.groupId)).thenReturn(Membership(userId: signedInUser.userId, publicSigningKey: Data(), groupId: meetup.groupId, admin: true, serverSignedMembershipCertificate: "serverSignedMembershipCertificate"))
        }
        
        let lastLocation = Location(latitude: 52.0, longitude: 13.0)
        stub(locationStorageManager) { stub in
            when(stub.loadLastLocation()).then { lastLocation }
        }
        
        stub(meetupManager) { stub in
            when(stub.reload(meetup: any())).thenReturn(Promise.value(meetup))
        }
        
        stub(chatManager) { stub in
            when(stub.add(message: any(), to: team.groupId)).then { message, _ in
                guard let message = message as? MetaMessage else { XCTFail(); return }
                XCTAssertEqual(message.message, LocalizedFormattedString("chat_meta_meetup_memberAdded_body", self.sender.publicName!))
            }
        }

        let notificationTitle = L10n.Notification.Meetup.MemberAdded.title(self.nameSupplier.name(user: self.sender))
        let notificationBody = L10n.Notification.Meetup.MemberAdded.body(self.nameSupplier.name(user: self.sender), self.nameSupplier.name(team: self.team))
        stub(notificationManager) { stub in
            when(stub.triggerNotification(title: notificationTitle, body: notificationBody, state: any(), category: any(), userInfo: any())).thenDoNothing()
        }
        
        stub(mailbox) { stub in
            when(stub.send(payloadContainer: any(), to: any(), serverSignedMembershipCertificate: any(), priority: any(), collapseId: any())).thenReturn(.value)
        }
        
        let completion = expectation(description: "Completion")
        groupNotificationReceiver.handleGroupUpdate(payload: payload, metaInfo: metaInfo) { result in
            XCTAssertEqual(result, .newData, "Invalid result")
            
            verify(self.meetupManager).reload(meetup: self.meetup)
            
            completion.fulfill()
        }
        
        wait(for: [completion])
        
        verify(notificationManager).triggerNotification(title: notificationTitle, body: notificationBody, state: any(), category: any(), userInfo: any())
    }
    
    func testTeamMemberUpdated() {
        let payload = GroupUpdate(groupId: team.groupId, action: .memberUpdated)
        let metaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: sender.userId, timestamp: Date(), collapseId: nil, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, conversationInvitation: nil)
        
        stub(userManager) { stub in
            when(stub.user(sender.userId)).thenReturn(sender)
        }
        
        stub(groupStorageManager) { stub in
            when(stub.loadTeam(team.groupId)).thenReturn(team)
            
            let senderMembership = Membership(userId: sender.userId, publicSigningKey: PublicKey(), groupId: team.groupId, admin: true, serverSignedMembershipCertificate: "certificate")
            when(stub.members(groupId: team.groupId)).thenReturn([Member(membership: senderMembership, user: sender)], [])
        }
        
        stub(teamManager) { stub in
            when(stub.reload(team: any(), reloadMeetup: true)).thenReturn(Promise.value(team))
        }
        
        let completion = expectation(description: "Completion")
        groupNotificationReceiver.handleGroupUpdate(payload: payload, metaInfo: metaInfo) { result in
            XCTAssertEqual(result, .newData, "Invalid result")
            
            verify(self.teamManager).reload(team: self.team, reloadMeetup: true)
            
            completion.fulfill()
        }
        
        wait(for: [completion])
    }
    
    func testMeetupMemberUpdated() {
        let payload = GroupUpdate(groupId: meetup.groupId, action: .memberUpdated)
        let metaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: sender.userId, timestamp: Date(), collapseId: nil, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, conversationInvitation: nil)
        
        stub(userManager) { stub in
            when(stub.user(sender.userId)).thenReturn(sender)
        }
        
        stub(groupStorageManager) { stub in
            when(stub.loadTeam(meetup.groupId)).thenReturn(nil)
            when(stub.loadMeetup(meetup.groupId)).thenReturn(meetup)
        }
        
        stub(meetupManager) { stub in
            when(stub.reload(meetup: any())).thenReturn(Promise.value(meetup))
        }
        
        let completion = expectation(description: "Completion")
        groupNotificationReceiver.handleGroupUpdate(payload: payload, metaInfo: metaInfo) { result in
            XCTAssertEqual(result, .newData, "Invalid result")
            
            verify(self.meetupManager).reload(meetup: self.meetup)
            
            completion.fulfill()
        }
        
        wait(for: [completion])
    }
    
    func testTeamMemberDeleted() {
        let payload = GroupUpdate(groupId: team.groupId, action: .memberDeleted)
        let metaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: sender.userId, timestamp: Date(), collapseId: nil, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, conversationInvitation: nil)
        
        stub(userManager) { stub in
            when(stub.user(sender.userId)).thenReturn(sender)
        }
        
        stub(groupStorageManager) { stub in
            when(stub.loadTeam(team.groupId)).thenReturn(team)
            
            let senderMembership = Membership(userId: sender.userId, publicSigningKey: PublicKey(), groupId: team.groupId, admin: true, serverSignedMembershipCertificate: "certificate")
            when(stub.members(groupId: team.groupId)).thenReturn([Member(membership: senderMembership, user: sender)], [])
        }
        
        stub(teamManager) { stub in
            when(stub.reload(team: any(), reloadMeetup: true)).thenReturn(Promise.value(team))
        }

        let notificationTitle = L10n.Notification.Group.MemberDeleted.title(self.nameSupplier.name(user: self.sender))
        let notificationBody = L10n.Notification.Group.MemberDeleted.body(self.nameSupplier.name(user: self.sender), self.nameSupplier.name(team: self.team))
        stub(notificationManager) { stub in
            when(stub.triggerNotification(title: notificationTitle, body: notificationBody, state: any(), category: any(), userInfo: any())).thenDoNothing()
        }
        
        stub(chatManager) { stub in
            when(stub.add(message: any(), to: team.groupId)).then { message, _ in
                guard let message = message as? MetaMessage else { XCTFail(); return }
                XCTAssertEqual(message.message, LocalizedString("chat_meta_group_memberDeleted_body"))
            }
        }
        
        let completion = expectation(description: "Completion")
        groupNotificationReceiver.handleGroupUpdate(payload: payload, metaInfo: metaInfo) { result in
            XCTAssertEqual(result, .newData, "Invalid result")
            
            verify(self.teamManager).reload(team: self.team, reloadMeetup: true)
            
            completion.fulfill()
        }
        
        wait(for: [completion])
        
        verify(notificationManager).triggerNotification(title: notificationTitle, body: notificationBody, state: any(), category: any(), userInfo: any())
        verify(chatManager).add(message: any(), to: any())
    }
    
    func testMeetupMemberDeleted() {
        let payload = GroupUpdate(groupId: meetup.groupId, action: .memberDeleted)
        let metaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: sender.userId, timestamp: Date(), collapseId: nil, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, conversationInvitation: nil)
        
        stub(userManager) { stub in
            when(stub.user(sender.userId)).thenReturn(sender)
        }
        
        stub(groupStorageManager) { stub in
            when(stub.loadTeam(meetup.groupId)).thenReturn(nil)
            when(stub.loadMeetup(meetup.groupId)).thenReturn(meetup)
            when(stub.teamOf(meetup: any())).thenReturn(team)
            
            let senderMembership = Membership(userId: sender.userId, publicSigningKey: PublicKey(), groupId: meetup.groupId, admin: true, serverSignedMembershipCertificate: "certificate")
            when(stub.members(groupId: meetup.groupId)).thenReturn([Member(membership: senderMembership, user: sender)], [])
        }
        
        stub(meetupManager) { stub in
            when(stub.reload(meetup: any())).thenReturn(Promise.value(meetup))
        }

        let notificationTitle = L10n.Notification.Meetup.MemberDeleted.title(self.nameSupplier.name(user: self.sender))
        let notificationBody = L10n.Notification.Meetup.MemberDeleted.body(self.nameSupplier.name(user: self.sender), self.nameSupplier.name(team: self.team))
        stub(notificationManager) { stub in
            when(stub.triggerNotification(title: notificationTitle, body: notificationBody, state: any(), category: any(), userInfo: any())).thenDoNothing()
        }
        
        stub(chatManager) { stub in
            when(stub.add(message: any(), to: team.groupId)).then { message, _ in
                guard let message = message as? MetaMessage else { XCTFail(); return }
                XCTAssertEqual(message.message, LocalizedString("chat_meta_meetup_memberDeleted_body"))
            }
        }
        
        let completion = expectation(description: "Completion")
        groupNotificationReceiver.handleGroupUpdate(payload: payload, metaInfo: metaInfo) { result in
            XCTAssertEqual(result, .newData, "Invalid result")
            
            verify(self.meetupManager).reload(meetup: self.meetup)
            
            completion.fulfill()
        }
        
        wait(for: [completion])
        
        verify(notificationManager).triggerNotification(title: notificationTitle, body: notificationBody, state: any(), category: any(), userInfo: any())
        verify(chatManager).add(message: any(), to: any())
    }
    
    func testChildGroupCreated() {
        let payload = GroupUpdate(groupId: team.groupId, action: .childGroupCreated)
        let metaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: sender.userId, timestamp: Date(), collapseId: nil, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, conversationInvitation: nil)
        
        team.meetupId = meetup.groupId
        
        stub(userManager) { stub in
            when(stub.user(sender.userId)).thenReturn(sender)
        }
        
        stub(groupStorageManager) { stub in
            when(stub.loadTeam(team.groupId)).thenReturn(team)
            when(stub.loadMeetup(meetup.groupId)).thenReturn(meetup)
        }
        
        stub(teamManager) { stub in
            when(stub.reload(team: any(), reloadMeetup: true)).thenReturn(Promise.value(team))
        }
        
        stub(meetupManager) { stub in
            when(stub.addOrReload(meetupId: meetup.groupId, teamId: team.groupId)).thenReturn(.value(meetup))
        }
        
        stub(chatManager) { stub in
            when(stub.add(message: any(), to: team.groupId)).then { message, _ in
                guard let message = message as? MetaMessage else { XCTFail(); return }
                XCTAssertEqual(message.message, LocalizedFormattedString("chat_meta_meetup_created_body", self.sender.publicName!))
            }
        }

        let notificationTitle = L10n.Notification.Meetup.Created.title
        let notificationBody = L10n.Notification.Meetup.Created.body(self.nameSupplier.name(user: self.sender), self.nameSupplier.name(team: self.team))
        stub(notificationManager) { stub in
            when(stub.triggerNotification(title: notificationTitle, body: notificationBody, state: any(), category: any(), userInfo: any())).thenDoNothing()
        }
        
        let completion = expectation(description: "Completion")
        groupNotificationReceiver.handleGroupUpdate(payload: payload, metaInfo: metaInfo) { result in
            XCTAssertEqual(result, .newData, "Invalid result")
            
            verify(self.teamManager).reload(team: self.team, reloadMeetup: true)
            
            completion.fulfill()
        }
        
        wait(for: [completion])
        
        verify(notificationManager).triggerNotification(title: notificationTitle, body: notificationBody, state: any(), category: any(), userInfo: any())
        verify(chatManager).add(message: any(), to: any())
    }
    
    func testChildGroupDeleted() {
        let payload = GroupUpdate(groupId: team.groupId, action: .childGroupDeleted)
        let metaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: sender.userId, timestamp: Date(), collapseId: nil, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, conversationInvitation: nil)
        
        stub(userManager) { stub in
            when(stub.user(sender.userId)).thenReturn(sender)
        }
        
        stub(groupStorageManager) { stub in
            when(stub.loadTeam(team.groupId)).thenReturn(team)
        }
        
        stub(teamManager) { stub in
            when(stub.reload(team: any(), reloadMeetup: true)).thenReturn(Promise.value(team))
        }
        
        stub(chatManager) { stub in
            when(stub.add(message: any(), to: team.groupId)).then { message, _ in
                guard let message = message as? MetaMessage else { XCTFail(); return }
                XCTAssertEqual(message.message, LocalizedFormattedString("chat_meta_meetup_deleted_body", self.sender.publicName!))
            }
        }

        let notificationTitle = L10n.Notification.Meetup.Deleted.title
        let notificationBody = L10n.Notification.Meetup.Deleted.body(self.nameSupplier.name(user: self.sender), self.nameSupplier.name(team: self.team))
        stub(notificationManager) { stub in
            when(stub.triggerNotification(title: notificationTitle, body: notificationBody, state: any(), category: any(), userInfo: any())).thenDoNothing()
        }
        
        let completion = expectation(description: "Completion")
        groupNotificationReceiver.handleGroupUpdate(payload: payload, metaInfo: metaInfo) { result in
            XCTAssertEqual(result, .newData, "Invalid result")
            
            verify(self.teamManager).reload(team: self.team, reloadMeetup: true)
            
            completion.fulfill()
        }
        
        wait(for: [completion])
        
        verify(notificationManager).triggerNotification(title: notificationTitle, body: notificationBody, state: any(), category: any(), userInfo: any())
        verify(chatManager).add(message: any(), to: any())
    }
    
    func testTeamUpdated() {
        let payload = GroupUpdate(groupId: team.groupId, action: .settingsUpdated)
        let metaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: sender.userId, timestamp: Date(), collapseId: nil, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, conversationInvitation: nil)
        
        stub(userManager) { stub in
            when(stub.user(sender.userId)).thenReturn(sender)
        }
        
        stub(groupStorageManager) { stub in
            when(stub.loadTeam(team.groupId)).thenReturn(team)
        }
        
        stub(teamManager) { stub in
            when(stub.reload(team: any(), reloadMeetup: true)).thenReturn(Promise.value(team))
        }

        let notificationTitle = L10n.Notification.Group.Updated.title
        let notificationBody = L10n.Notification.Group.Updated.body(self.nameSupplier.name(user: self.sender), self.nameSupplier.name(team: self.team))
        stub(notificationManager) { stub in
            when(stub.triggerNotification(title: notificationTitle, body: notificationBody, state: any(), category: any(), userInfo: any())).thenDoNothing()
        }
        
        stub(chatManager) { stub in
            when(stub.add(message: any(), to: team.groupId)).then { message, _ in
                guard let message = message as? MetaMessage else { XCTFail(); return }
                XCTAssertEqual(message.message, LocalizedFormattedString("chat_meta_group_updated_body", self.sender.publicName!))
            }
        }
        
        let completion = expectation(description: "Completion")
        groupNotificationReceiver.handleGroupUpdate(payload: payload, metaInfo: metaInfo) { result in
            XCTAssertEqual(result, .newData, "Invalid result")
            
            verify(self.teamManager).reload(team: self.team, reloadMeetup: true)
            
            completion.fulfill()
        }
        
        wait(for: [completion])
        
        verify(notificationManager).triggerNotification(title: notificationTitle, body: notificationBody, state: any(), category: any(), userInfo: any())
        verify(chatManager).add(message: any(), to: any())
    }
    
    func testMeetupUpdated() {
        let payload = GroupUpdate(groupId: meetup.groupId, action: .settingsUpdated)
        let metaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: sender.userId, timestamp: Date(), collapseId: nil, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, conversationInvitation: nil)
        
        stub(userManager) { stub in
            when(stub.user(sender.userId)).thenReturn(sender)
        }
        
        stub(groupStorageManager) { stub in
            when(stub.loadTeam(meetup.groupId)).thenReturn(nil)
            when(stub.loadMeetup(meetup.groupId)).thenReturn(meetup)
            when(stub.teamOf(meetup: any())).thenReturn(team)
        }
        
        stub(meetupManager) { stub in
            when(stub.reload(meetup: any())).thenReturn(Promise.value(meetup))
        }

        let notificationTitle = L10n.Notification.Meetup.Updated.title
        let notificationBody = L10n.Notification.Meetup.Updated.body(self.nameSupplier.name(user: self.sender), self.nameSupplier.name(team: self.team))
        stub(notificationManager) { stub in
            when(stub.triggerNotification(title: notificationTitle, body: notificationBody, state: any(), category: any(), userInfo: any())).thenDoNothing()
        }
        
        stub(chatManager) { stub in
            when(stub.add(message: any(), to: team.groupId)).then { message, _ in
                guard let message = message as? MetaMessage else { XCTFail(); return }
                XCTAssertEqual(message.message, LocalizedFormattedString("chat_meta_meetup_updated_body", self.sender.publicName!))
            }
        }
        
        let completion = expectation(description: "Completion")
        groupNotificationReceiver.handleGroupUpdate(payload: payload, metaInfo: metaInfo) { result in
            XCTAssertEqual(result, .newData, "Invalid result")
            
            verify(self.meetupManager).reload(meetup: self.meetup)
            
            completion.fulfill()
        }
        
        wait(for: [completion])
        
        verify(notificationManager).triggerNotification(title: notificationTitle, body: notificationBody, state: any(), category: any(), userInfo: any())
        verify(chatManager).add(message: any(), to: any())
    }
    
    func testUserExcluded() {
        let payload = GroupUpdate(groupId: team.groupId, action: .settingsUpdated)
        let metaInfo = PayloadMetaInfo(envelopeId: MessageId(), senderId: sender.userId, timestamp: Date(), collapseId: nil, senderServerSignedMembershipCertificate: nil, receiverServerSignedMembershipCertificate: nil, conversationInvitation: nil)
        
        stub(groupStorageManager) { stub in
            when(stub.loadTeam(team.groupId)).thenReturn(team)
        }
        
        stub(teamManager) { stub in
            when(stub.reload(team: any(), reloadMeetup: true)).thenReturn(Promise(error: BackendError.unauthorized))
        }

        let notificationTitle = L10n.Notification.Group.Excluded.title
        let notificationBody = L10n.Notification.Group.Excluded.body
        stub(notificationManager) { stub in
            when(stub.triggerNotification(title: any(), body: any(), state: any(), category: any(), userInfo: any())).thenDoNothing()
            when(stub.triggerNotification(title: notificationTitle, body: notificationBody, state: any(), category: any(), userInfo: any())).thenDoNothing()
        }
        
        let completion = expectation(description: "Completion")
        groupNotificationReceiver.handleGroupUpdate(payload: payload, metaInfo: metaInfo) { result in
            XCTAssertEqual(result, .newData, "Invalid result")
            
            verify(self.teamManager).reload(team: self.team, reloadMeetup: true)
            verify(self.notificationManager).triggerNotification(title: notificationTitle, body: notificationBody, state: any(), category: any(), userInfo: any())
            
            completion.fulfill()
        }
        
        wait(for: [completion])
        
        verify(notificationManager).triggerNotification(title: notificationTitle, body: notificationBody, state: any(), category: any(), userInfo: any())
    }
}
