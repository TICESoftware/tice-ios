//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UserNotifications
import TICEAPIModels
import PromiseKit
import Swinject
import Chatto

enum GroupNotificationError: LocalizedError {
    case invalidAction(GroupUpdate)
    case groupNotFound
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidAction(let groupUpdate): return "Invalid action in group: \(groupUpdate)"
        case .groupNotFound: return "Group was not found"
        case .invalidResponse : return "Invalid response"
        }
    }
}

class GroupNotificationReceiver: GroupNotificationReceiverType {

    weak var postOffice: PostOfficeType?
    weak var messageSender: MessageSenderType?
    weak var notificationManager: NotificationManagerType?
    
    let teamManager: TeamManagerType
    let groupStorageManager: GroupStorageManagerType
    let meetupManager: MeetupManagerType
    let locationManager: LocationManagerType
    let locationStorageManager: LocationStorageManagerType
    let locationSharingManager: LocationSharingManagerType
    let userManager: UserManagerType
    let nameSupplier: NameSupplierType
    let chatManager: ChatManagerType
	let deepLinkParser: DeepLinkParserType
    let mailbox: MailboxType
    let signedInUser: SignedInUser

    init(postOffice: PostOfficeType, teamManager: TeamManagerType, groupStorageManager: GroupStorageManagerType, notificationManager: NotificationManagerType, meetupManager: MeetupManagerType, locationManager: LocationManagerType, locationStorageManager: LocationStorageManagerType, locationSharingManager: LocationSharingManagerType, userManager: UserManagerType, nameSupplier: NameSupplierType, chatManager: ChatManagerType, deepLinkParser: DeepLinkParserType, messageSender: MessageSenderType, mailbox: MailboxType, signedInUser: SignedInUser) {
        self.postOffice = postOffice
        self.teamManager = teamManager
        self.groupStorageManager = groupStorageManager
        self.notificationManager = notificationManager
        self.meetupManager = meetupManager
        self.locationManager = locationManager
        self.locationStorageManager = locationStorageManager
        self.locationSharingManager = locationSharingManager
        self.userManager = userManager
        self.nameSupplier = nameSupplier
        self.chatManager = chatManager
        self.deepLinkParser = deepLinkParser
        self.messageSender = messageSender
        self.mailbox = mailbox
        self.signedInUser = signedInUser
    }

    deinit {
        self.postOffice?.handlers[.groupUpdateV1] = nil
        self.notificationManager?.handlers[.join] = nil
        self.notificationManager?.handlers[.respond] = nil
        self.postOffice?.handlers[.locationSharingUpdateV1] = nil
    }

    func registerHandler() {
        guard self.postOffice?.handlers[.groupUpdateV1] == nil else {
            logger.debug("Handler for group update already registered.")
            return
        }

        self.postOffice?.handlers[.groupUpdateV1] = { [unowned self] in
            handleGroupUpdate(payload: $0, metaInfo: $1, completion: $2)
        }
        
        self.postOffice?.handlers[.locationSharingUpdateV1] = { [unowned self] in
            handleLocationSharingUpdate(payload: $0, metaInfo: $1, completion: $2)
        }
        
        self.notificationManager?.handlers[.join] = { [unowned self] in join(response: $0) }
        self.notificationManager?.handlers[.respond] = { [unowned self] in respond(response: $0) }
    }

    func handleGroupUpdate(payload: Payload, metaInfo: PayloadMetaInfo, completion: PostOfficeType.PayloadHandler?) {
        guard let payload = payload as? GroupUpdate else {
            logger.error("Invalid payload type. Expected group update.")
            completion?(.failed)
            return
        }

        firstly { () -> Promise<Void> in
            if let team = try groupStorageManager.loadTeam(payload.groupId) {
                return self.handleTeamUpdate(team: team, update: payload, metaInfo: metaInfo)
            } else if let meetup = try groupStorageManager.loadMeetup(payload.groupId) {
                return self.handleMeetupUpdate(meetup: meetup, update: payload, metaInfo: metaInfo)
            } else {
                throw GroupNotificationError.groupNotFound
            }
        }.done {
            completion?(.newData)
        }.catch { error in
            if case BackendError.unauthorized = error {
                logger.info("User not member of group \(payload.groupId). Has probably been excluded.")

                let title = L10n.Notification.Group.Excluded.title
                let body = L10n.Notification.Group.Excluded.body
                
                self.notificationManager?.triggerNotification(title: title, body: body, state: .main(.groups), category: nil, userInfo: [:])

                completion?(.newData)
                return
            }

            logger.error(error)
            completion?(.failed)
        }
    }

    private func handleTeamUpdate(team: Team, update: GroupUpdate, metaInfo: PayloadMetaInfo) -> Promise<Void> {
        switch update.action {
        case .groupDeleted:
            return handleDeletion(team: team, metaInfo: metaInfo)
        case .memberAdded:
            return handleMemberAdded(team: team, metaInfo: metaInfo)
        case .memberUpdated:
            return handleMemberUpdated(team: team, metaInfo: metaInfo)
        case .memberDeleted:
            return handleMemberDeleted(team: team, metaInfo: metaInfo)
        case .childGroupCreated:
            return handleChildGroupCreated(team: team, metaInfo: metaInfo)
        case .childGroupDeleted:
            return handleChildGroupDeleted(team: team, metaInfo: metaInfo)
        default:
            return handleTeamUpdated(team: team, metaInfo: metaInfo)
        }
    }

    private func handleMeetupUpdate(meetup: Meetup, update: GroupUpdate, metaInfo: PayloadMetaInfo) -> Promise<Void> {
        switch update.action {
        case .groupDeleted:
            return handleDeletion(meetup: meetup, metaInfo: metaInfo)
        case .memberAdded:
            return handleMemberAdded(meetup: meetup, metaInfo: metaInfo)
        case .memberUpdated:
            return handleMemberUpdated(meetup: meetup, metaInfo: metaInfo)
        case .memberDeleted:
            return handleMemberDeleted(meetup: meetup, metaInfo: metaInfo)
        case .childGroupCreated:
            return .init(error: GroupNotificationError.invalidAction(update))
        case .childGroupDeleted:
            return .init(error: GroupNotificationError.invalidAction(update))
        default:
            return handleMeetupUpdated(meetup: meetup, metaInfo: metaInfo)
        }
    }

    private func userName(userId: UserId) -> String {
        guard let user = userManager.user(userId) else {
            return L10n.User.Name.someone
        }

        return nameSupplier.name(user: user)
    }

    private func handleDeletion(team: Team, metaInfo: PayloadMetaInfo) -> Promise<Void> {
        let groupName = nameSupplier.name(team: team)
        let userName = self.userName(userId: metaInfo.senderId)

        let title = L10n.Notification.Group.Deleted.title
        let body = L10n.Notification.Group.Deleted.body(userName, groupName)
        
        notificationManager?.triggerNotification(title: title, body: body, state: .main(.team(team: team.groupId)), category: nil, userInfo: ["teamId": team.groupId.uuidString])

        return firstly { () -> Promise<Void> in
            try groupStorageManager.removeTeam(team.groupId)
            return .init()
        }
    }

    private func handleDeletion(meetup: Meetup, metaInfo: PayloadMetaInfo) -> Promise<Void> {
        return firstly { () -> Promise<Void> in
            try groupStorageManager.removeMeetup(meetup: meetup)
            let team = try groupStorageManager.teamOf(meetup: meetup)

            return teamManager.reload(team: team, reloadMeetup: true).asVoid()
        }
    }

    private func handleMemberAdded(team: Team, metaInfo: PayloadMetaInfo) -> Promise<Void> {
        firstly {
            userManager.getUser(metaInfo.senderId)
        }.then { user -> Promise<Team> in
            let groupName = self.nameSupplier.name(team: team)
            let userName = self.nameSupplier.name(user: user)

            let title = L10n.Notification.Group.MemberAdded.title(userName)
            let body = L10n.Notification.Group.MemberAdded.body(userName, groupName)
            let metaMessage = L10n.Chat.Meta.Group.MemberAdded.body(userName)
            
            self.notificationManager?.triggerNotification(title: title, body: body, state: .main(.team(team: team.groupId)), category: nil, userInfo: ["teamId": team.groupId.uuidString])
            self.createMetaMessage(team: team, message: metaMessage, date: metaInfo.timestamp)

            return self.teamManager.reload(team: team, reloadMeetup: true)
        }.then { reloadedTeam -> Promise<Member> in
            let membership = try self.groupStorageManager.loadMembership(userId: metaInfo.senderId, groupId: reloadedTeam.groupId)
            return self.userManager.getUser(membership.userId).map { Member(membership: membership, user: $0) }
        }.then { member -> Promise<Void> in
            let lastLocationSharingState = self.locationSharingManager.locationSharingState(userId: self.signedInUser.userId, groupId: team.groupId)
            guard lastLocationSharingState.enabled else { return .value }
            
            guard let lastLocation = self.locationManager.lastUserLocation else {
                logger.warning("Sending last location to just joined member \(member.user.userId) failed as we have no last location.")
                return .value
            }
            
            let ownMembership = try self.groupStorageManager.loadMembership(userId: self.signedInUser.userId, groupId: team.groupId)
            return firstly { () -> Promise<Void> in
                logger.debug("Sending last location sharing state to just joined member \(member.user.userId)")
                let payload = LocationSharingUpdate(groupId: team.groupId, sharingEnabled: lastLocationSharingState.enabled)
                let payloadContainer = PayloadContainer(payloadType: .locationSharingUpdateV1, payload: payload)
                return self.mailbox.send(payloadContainer: payloadContainer,
                                         to: [member.membership],
                                         serverSignedMembershipCertificate: ownMembership.serverSignedMembershipCertificate,
                                         priority: .deferred,
                                         collapseId: nil)
            }.recover { error in
                logger.warning("Could not send last location sharing state. Reason: \(error)")
            }.then { () -> Promise<Void> in
                logger.debug("Sending last location to just joined member \(member.user.userId)")
                let payload = LocationUpdateV2(location: lastLocation, groupId: team.groupId)
                let payloadContainer = PayloadContainer(payloadType: .locationUpdateV2, payload: payload)
                return self.mailbox.send(payloadContainer: payloadContainer,
                                         to: [member.membership],
                                         serverSignedMembershipCertificate: ownMembership.serverSignedMembershipCertificate,
                                         priority: .deferred,
                                         collapseId: .locationUpdate)
            }.recover { error in
                logger.warning("Could not send last location. Reason: \(error)")
            }
        }
    }

    private func handleMemberAdded(meetup: Meetup, metaInfo: PayloadMetaInfo) -> Promise<Void> {
        return firstly {
            meetupManager.reload(meetup: meetup)
        }.then { reloadedMeetup -> Promise<Member> in
            let membership = try self.groupStorageManager.loadMembership(userId: metaInfo.senderId, groupId: reloadedMeetup.groupId)
            return self.userManager.getUser(membership.userId).map { Member(membership: membership, user: $0) }
        }.map { member -> Member in
            let userName = self.nameSupplier.name(user: member.user)
            let team = try self.groupStorageManager.teamOf(meetup: meetup)
            let groupName = self.nameSupplier.name(team: team)
            let title = L10n.Notification.Meetup.MemberAdded.title(userName)
            let body = L10n.Notification.Meetup.MemberAdded.body(userName, groupName)
			let appState = AppState.main(.team(team: team.groupId))
            let userInfo = ["teamId": team.groupId.uuidString]

            let metaMessage = L10n.Chat.Meta.Meetup.MemberAdded.body(userName)
            self.createMetaMessage(team: team, message: metaMessage, date: metaInfo.timestamp)

            self.notificationManager?.triggerNotification(title: title, body: body, state: appState, category: nil, userInfo: userInfo)
            return member
        }.then { member -> Promise<Void> in
            guard let lastLocation = try? self.locationStorageManager.loadLastLocation(),
                  let ownMembership = try? self.groupStorageManager.loadMembership(userId: self.signedInUser.userId, groupId: meetup.groupId)
                  else {
                return .value
            }
            
            let payload = LocationUpdate(location: lastLocation)
            let payloadContainer = PayloadContainer(payloadType: .locationUpdateV1, payload: payload)
            return self.mailbox.send(payloadContainer: payloadContainer,
                                     to: [member.membership],
                                     serverSignedMembershipCertificate: ownMembership.serverSignedMembershipCertificate,
                                     priority: .deferred,
                                     collapseId: .locationUpdate)
        }
    }
    
    private func handleMemberUpdated(team: Team, metaInfo: PayloadMetaInfo) -> Promise<Void> {
        logger.debug("A member in team \(team.groupId) has been updated. Reloading team.")
        return teamManager.reload(team: team, reloadMeetup: true).asVoid()
    }
    
    private func handleMemberUpdated(meetup: Meetup, metaInfo: PayloadMetaInfo) -> Promise<Void> {
        logger.debug("A member in meetup \(meetup.groupId) has been updated. Reloading meetup.")
        return meetupManager.reload(meetup: meetup).asVoid()
    }

    private func handleMemberDeleted(team: Team, metaInfo: PayloadMetaInfo) -> Promise<Void> {
        firstly { () -> Promise<[User]> in
            let knownMembers = try groupStorageManager.members(groupId: team.groupId)
            return teamManager.reload(team: team, reloadMeetup: true).map { _ in
                let updatedMembers = try self.groupStorageManager.members(groupId: team.groupId)
                let deletedMembers = knownMembers.filter { knownMember in
                    !updatedMembers.contains(where: { knownMember.user.userId == $0.user.userId })
                }
                return deletedMembers.map(\.user)
            }
        }.done { users in
            let groupName = self.nameSupplier.name(team: team)
            let userNames = users.map { self.nameSupplier.name(user: $0) }
            let userList = LocalizedList(userNames)
            let title = L10n.Notification.Group.MemberDeleted.title(userList)
            let bodyClosure = userNames.count > 1 ? L10n.Notification.Group.MembersDeleted.body : L10n.Notification.Group.MemberDeleted.body
            let body = bodyClosure(userList, groupName)
            self.notificationManager?.triggerNotification(title: title, body: body, state: .main(.team(team: team.groupId)), category: nil, userInfo: ["teamId": team.groupId.uuidString])
            
            let metaMessage = L10n.Chat.Meta.Group.MemberDeleted.body
            self.createMetaMessage(team: team, message: metaMessage, date: metaInfo.timestamp)
        }
    }

    private func handleMemberDeleted(meetup: Meetup, metaInfo: PayloadMetaInfo) -> Promise<Void> {
        firstly { () -> Promise<[User]> in
            let knownMembers = try groupStorageManager.members(groupId: meetup.groupId)
            return meetupManager.reload(meetup: meetup).map { _ in
                let updatedMembers = try self.groupStorageManager.members(groupId: meetup.groupId)
                let deletedMembers = knownMembers.filter { knownMember in
                    !updatedMembers.contains(where: { knownMember.user.userId == $0.user.userId })
                }
                return deletedMembers.map(\.user)
            }
        }.done { users in
            let userNames = users.map { self.nameSupplier.name(user: $0) }
            let userList = LocalizedList(userNames)
			let team = try self.groupStorageManager.teamOf(meetup: meetup)
            let groupName = self.nameSupplier.name(team: team)
            let title = L10n.Notification.Meetup.MemberDeleted.title(userList)

            let bodyClosure = userNames.count > 1 ? L10n.Notification.Meetup.MembersDeleted.body : L10n.Notification.Meetup.MemberDeleted.body
            let body = bodyClosure(userList, groupName)
            let appState = AppState.main(.team(team: team.groupId))
            let userInfo = ["teamId": team.groupId.uuidString]
        
            let metaMessage = L10n.Chat.Meta.Meetup.MemberDeleted.body
            self.createMetaMessage(team: team, message: metaMessage, date: metaInfo.timestamp)
            
            self.notificationManager?.triggerNotification(title: title, body: body, state: appState, category: nil, userInfo: userInfo)
        }
    }

    private func handleChildGroupCreated(team: Team, metaInfo: PayloadMetaInfo) -> Promise<Void> {
        return firstly {
            teamManager.reload(team: team, reloadMeetup: true)
        }.done { reloadedTeam in
            guard let meetupId = reloadedTeam.meetupId,
                  let meetup = try self.groupStorageManager.loadMeetup(meetupId) else {
                throw GroupNotificationError.groupNotFound
            }
            
            let groupName = self.nameSupplier.name(team: team)
            let userName = self.userName(userId: metaInfo.senderId)
            let title = L10n.Notification.Meetup.Created.title
            let body = L10n.Notification.Meetup.Created.body(userName, groupName)
            let metaMessage = L10n.Chat.Meta.Meetup.Created.body(userName)
            
            let state = AppState.main(.meetupSettings(team: team.groupId, meetup: meetup.groupId))
            let userInfo = ["teamId": team.groupId.uuidString, "meetupId": meetup.groupId.uuidString]
            self.notificationManager?.triggerNotification(title: title, body: body, state: state, category: .meetingCreated, userInfo: userInfo)
            self.createMetaMessage(team: team, message: metaMessage, date: metaInfo.timestamp)
        }
    }

    private func handleChildGroupDeleted(team: Team, metaInfo: PayloadMetaInfo) -> Promise<Void> {
        firstly {
            teamManager.reload(team: team, reloadMeetup: true).asVoid()
        }.done {
            let groupName = self.nameSupplier.name(team: team)
            let userName = self.userName(userId: metaInfo.senderId)
            let title = L10n.Notification.Meetup.Deleted.title
            let body = L10n.Notification.Meetup.Deleted.body(userName, groupName)
            let metaMessage = L10n.Chat.Meta.Meetup.Deleted.body(userName)
            
            self.notificationManager?.triggerNotification(title: title, body: body, state: .main(.team(team: team.groupId)), category: nil, userInfo: ["teamId": team.groupId.uuidString])
            self.createMetaMessage(team: team, message: metaMessage, date: metaInfo.timestamp)
        }
    }

    private func handleTeamUpdated(team: Team, metaInfo: PayloadMetaInfo) -> Promise<Void> {
        firstly {
            teamManager.reload(team: team, reloadMeetup: true)
        }.done { reloadedTeam in
            let groupName = self.nameSupplier.name(team: reloadedTeam)
            let userName = self.userName(userId: metaInfo.senderId)
            let title = L10n.Notification.Group.Updated.title
            let body = L10n.Notification.Group.Updated.body(userName, groupName)
            let metaMessage = L10n.Chat.Meta.Group.Updated.body(userName)
            
            self.createMetaMessage(team: reloadedTeam, message: metaMessage, date: metaInfo.timestamp)
            self.notificationManager?.triggerNotification(title: title, body: body, state: .main(.team(team: reloadedTeam.groupId)), category: nil, userInfo: ["teamId": reloadedTeam.groupId.uuidString])
        }.asVoid()
    }

    private func handleMeetupUpdated(meetup: Meetup, metaInfo: PayloadMetaInfo) -> Promise<Void> {
        firstly {
            meetupManager.reload(meetup: meetup)
        }.map { reloadedMeetup in
            try self.groupStorageManager.teamOf(meetup: reloadedMeetup)
        }.done { team in
            let userName = self.userName(userId: metaInfo.senderId)
            let title = L10n.Notification.Meetup.Updated.title
            let groupName = self.nameSupplier.name(team: team)
            let body = L10n.Notification.Meetup.Updated.body(userName, groupName)
            
            let metaMessage = L10n.Chat.Meta.Meetup.Updated.body(userName)
            self.createMetaMessage(team: team, message: metaMessage, date: metaInfo.timestamp)

            let appState = AppState.main(.team(team: team.groupId))
            let userInfo = ["teamId": team.groupId.uuidString]
            self.notificationManager?.triggerNotification(title: title, body: body, state: appState, category: nil, userInfo: userInfo)
        }.asVoid()
    }
    
    private func createMetaMessage(team: Team, message: String, date: Date) {
        let metaMessage = MetaMessage(uid: UUID().uuidString,
                                      date: date,
                                      message: message,
                                      read: true)
        chatManager.add(message: metaMessage, to: team.groupId)
    }
    
    private func join(response: UNNotificationResponse) -> Promise<AppState?> {
        logger.info("Join meetup because of \(response)")
        return firstly { () -> Promise<Void> in
            guard let meetupIdString = response.notification.request.content.userInfo["meetupId"] as? String,
                let meetupId = GroupId(uuidString: meetupIdString),
                let meetup = try self.groupStorageManager.loadMeetup(meetupId) else {
                    throw GroupNotificationError.groupNotFound
            }
            return self.meetupManager.join(meetup)
        }.map {
            guard let teamIdString = response.notification.request.content.userInfo["teamId"] as? String,
                let teamId = GroupId(uuidString: teamIdString) else { return nil }
            return AppState.main(.team(team: teamId))
        }
    }
    
    private func respond(response: UNNotificationResponse) -> Promise<AppState?> {
        logger.info("Send message \(response)")
        return firstly { () -> Promise<UpdateType?> in
            guard let messageSender = messageSender else {
                return Promise.value(nil)
            }
            
            guard let textResponse = response as? UNTextInputNotificationResponse else {
                throw GroupNotificationError.invalidResponse
            }
            
            guard let teamIdString = response.notification.request.content.userInfo["teamId"] as? String,
                let teamId = GroupId(uuidString: teamIdString),
                let team = try self.groupStorageManager.loadTeam(teamId) else {
                    throw GroupNotificationError.groupNotFound
            }
            
            if let messageId = response.notification.request.content.userInfo["messageId"] as? String {
                chatManager.markAsRead(messageId: messageId, groupId: teamId)
            }
            
            return messageSender.send(text: textResponse.userText, team: team)
        }.map { _ in
            return nil
        }
    }
    
    private func handleLocationSharingUpdate(payload: Payload, metaInfo: PayloadMetaInfo, completion: PostOfficeType.PayloadHandler?) {
        guard let locationSharingUpdate = payload as? LocationSharingUpdate else {
            logger.error("Invalid payload type. Expected location sharing update payload.")
            completion?(.failed)
            return
        }
        
        do {
            try locationStorageManager.storeLocationSharingState(userId: metaInfo.senderId,
                                                                 groupId: locationSharingUpdate.groupId,
                                                                 enabled: locationSharingUpdate.sharingEnabled,
                                                                 lastUpdated: metaInfo.timestamp)
        } catch {
            logger.error("Storing location sharing state for \(metaInfo.senderId) in group \(locationSharingUpdate.groupId) failed. Reason: \(error)")
            completion?(.failed)
            return
        }
        
        guard let team = teamManager.teamWith(groupId: locationSharingUpdate.groupId) else {
            logger.warning("Received location sharing state for unknown team")
            completion?(.failed)
            return
        }
        
        let userName = self.userName(userId: metaInfo.senderId)
        let groupName = nameSupplier.name(team: team)
        
        let notificationType = L10n.Notification.LocationSharing.OthersSharing.Notification.self
        
        let title: String
        let body: String
        let metaMessage: String
        if locationSharingUpdate.sharingEnabled {
            title = notificationType.Enabled.title(userName)
            body = notificationType.Enabled.body(userName, groupName)
            metaMessage = notificationType.Enabled.meta(userName)
        } else {
            title = notificationType.Disabled.title(userName)
            body = notificationType.Disabled.body(userName, groupName)
            metaMessage = notificationType.Disabled.meta(userName)
        }
        createMetaMessage(team: team, message: metaMessage, date: metaInfo.timestamp)
        
        let appState = AppState.main(.team(team: team.groupId))
        let userInfo = ["teamId": team.groupId.uuidString]
        self.notificationManager?.triggerNotification(title: title, body: body, state: appState, category: nil, userInfo: userInfo)
        completion?(.newData)
    }
}
