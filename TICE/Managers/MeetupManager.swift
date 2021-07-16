//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels
import ConvAPI
import PromiseKit
import CoreLocation
import TICEAuth

enum MeetupManagerError: LocalizedError {
    case couldNotAccessSignedInUser
    case didNotFindGroup
    case permissionDenied
    case meetupAlreadyRunning
    case parentKeyMissing

    var errorDescription: String? {
        switch self {
        case .couldNotAccessSignedInUser: return L10n.Error.MeetupManager.couldNotAccessSignedInUser
        case .didNotFindGroup: return L10n.Error.MeetupManager.didNotFindGroup
        case .permissionDenied: return L10n.Error.MeetupManager.permissionDenied
        case .meetupAlreadyRunning: return L10n.Error.MeetupManager.meetupAlreadyRunning
        case .parentKeyMissing: return L10n.Error.MeetupManager.parentKeyMissing
        }
    }
}

enum MeetupState {
    case none
    case invited(Meetup)
    case participating(Meetup)
}

extension Envelope.CollapseIdentifier {
    static var locationUpdate: Envelope.CollapseIdentifier { UUID(uuidString: "00000000-0000-0000-0001-000000000000")!.uuidString }
}

class MeetupManager: MeetupManagerType {
    let groupManager: GroupManagerType
    let groupStorageManager: GroupStorageManagerType
    let signedInUser: SignedInUser
    let cryptoManager: CryptoManagerType
    let authManager: AuthManagerType
    let locationManager: LocationManagerType
    let backend: TICEAPI
    let encoder: JSONEncoder
    let decoder: JSONDecoder
    let tracker: TrackerType
    
    weak var teamReloader: TeamReloader?

    @SynchronizedProperty var reloadTimeouts: [GroupId: Date] = [:]

    let reloadTimeout: TimeInterval

    init(groupManager: GroupManagerType, groupStorageManager: GroupStorageManagerType, signedInUser: SignedInUser, cryptoManager: CryptoManagerType, authManager: AuthManagerType, locationManager: LocationManagerType, backend: TICEAPI, encoder: JSONEncoder, decoder: JSONDecoder, tracker: TrackerType, reloadTimeout: TimeInterval) {
        self.groupManager = groupManager
        self.groupStorageManager = groupStorageManager
        self.signedInUser = signedInUser
        self.cryptoManager = cryptoManager
        self.authManager = authManager
        self.locationManager = locationManager
        self.backend = backend
        self.encoder = encoder
        self.decoder = decoder
        self.tracker = tracker

        self.reloadTimeout = reloadTimeout
    }

    func meetupWith(groupId: GroupId) -> Meetup? {
        do {
            return try groupStorageManager.loadMeetup(groupId)
        } catch {
            logger.error("Failed to load meetups: \(String(describing: error))")
            return nil
        }
    }

    func createMeetup(in team: Team, at location: Location?, joinMode: JoinMode, permissionMode: PermissionMode) -> Promise<Meetup> {
        let groupId = GroupId()
        let groupKey = cryptoManager.generateGroupKey()

        return firstly { () -> Promise<CreateGroupResponse> in
            guard try groupStorageManager.meetupIn(team: team) == nil else {
                return Promise(error: MeetupManagerError.meetupAlreadyRunning)
            }

            let groupSettings = GroupSettings(owner: signedInUser.userId, name: nil)
            let internalSettings = InternalMeetupSettings(location: location)

            let groupSettingsData = try encoder.encode(groupSettings)
            let internalSettingsData = try encoder.encode(internalSettings)

            let encryptedGroupSettings = try cryptoManager.encrypt(groupSettingsData, secretKey: groupKey)
            let encryptedInternalSettings = try cryptoManager.encrypt(internalSettingsData, secretKey: groupKey)

            let selfSignedAdminCertificate = try authManager.createUserSignedMembershipCertificate(userId: signedInUser.userId, groupId: groupId, admin: true, issuerUserId: signedInUser.userId, signingKey: signedInUser.privateSigningKey)

            let parentEncryptedChildGroupKey = try cryptoManager.encrypt(groupKey, secretKey: team.groupKey)
            let parentGroup = ParentGroup(groupId: team.groupId, encryptedChildGroupKey: parentEncryptedChildGroupKey)

            return backend.createGroup(userId: signedInUser.userId,
                                           type: .meetup,
                                           joinMode: joinMode,
                                           permissionMode: permissionMode,
                                           groupId: groupId,
                                           parentGroup: parentGroup,
                                           selfSignedAdminCertificate: selfSignedAdminCertificate,
                                           encryptedSettings: encryptedGroupSettings,
                                           encryptedInternalSettings: encryptedInternalSettings)
        }.then { createGroupResponse -> Promise<Meetup> in
            var meetup = Meetup(groupId: groupId, groupKey: groupKey, owner: self.signedInUser.userId, joinMode: joinMode, permissionMode: permissionMode, tag: createGroupResponse.groupTag, teamId: team.groupId, meetingPoint: location, locationSharingEnabled: true)
            return firstly {
                self.groupManager.addUserMember(into: meetup, admin: true, serverSignedMembershipCertificate: createGroupResponse.serverSignedAdminCertificate)
            }.then { membership, updatedGroupTag -> Promise<Meetup> in

                meetup.tag = updatedGroupTag
                try self.groupStorageManager.storeMeetup(meetup)
                try self.groupStorageManager.store(membership)

                self.resetReloadTimeout(groupId: groupId)

                return self.groupManager.sendGroupUpdateNotification(to: team, action: .childGroupCreated).map { meetup }
            }
        }.then { meetup -> Promise<Meetup> in
            guard let teamReloader = self.teamReloader else {
                logger.error("Team reloader not set.")
                return .value(meetup)
            }
            return teamReloader.reload(team: team).map { meetup }
        }
    }

    struct FetchedMeetup {
        var meetup: Meetup
        var memberships: [Membership]
    }

    enum MeetupDecryptionKey {
        case meetupKey(SecretKey)
        case parentKey(SecretKey)
    }

    private func fetchMeetup(groupId: GroupId, decryptionKey: MeetupDecryptionKey, serverSignedMembershipCertificate: Certificate, groupTag: GroupTag?) -> Promise<FetchedMeetup> {
        return firstly {
            backend.getGroupInternals(groupId: groupId, serverSignedMembershipCertificate: serverSignedMembershipCertificate, groupTag: groupTag)
        }.map { groupInternalsResponse -> FetchedMeetup in
            let groupKey: SecretKey

            switch decryptionKey {
            case .meetupKey(let meetupKey):
                groupKey = meetupKey
            case .parentKey(let parentKey):
                guard let encryptedGroupKey = groupInternalsResponse.parentEncryptedGroupKey else {
                    throw MeetupManagerError.parentKeyMissing
                }
                groupKey = try self.cryptoManager.decrypt(encryptedData: encryptedGroupKey, secretKey: parentKey)
            }

            let settingsPlaintext = try self.cryptoManager.decrypt(encryptedData: groupInternalsResponse.encryptedSettings, secretKey: groupKey)
            let settings = try self.decoder.decode(GroupSettings.self, from: settingsPlaintext)

            let internalSettingsPlaintext = try self.cryptoManager.decrypt(encryptedData: groupInternalsResponse.encryptedInternalSettings, secretKey: groupKey)
            let internalSettings = try self.decoder.decode(InternalMeetupSettings.self, from: internalSettingsPlaintext)

            let memberships = try groupInternalsResponse.encryptedMemberships.map { encryptedMembership -> Membership in
                let membershipPlaintext = try self.cryptoManager.decrypt(encryptedData: encryptedMembership, secretKey: groupKey)
                return try self.decoder.decode(Membership.self, from: membershipPlaintext)
            }

            guard let teamId = groupInternalsResponse.parentGroupId else {
                throw MeetupManagerError.didNotFindGroup
            }

            let meetup = Meetup(groupId: groupId, groupKey: groupKey, owner: settings.owner, joinMode: groupInternalsResponse.joinMode, permissionMode: groupInternalsResponse.permissionMode, tag: groupInternalsResponse.groupTag, teamId: teamId, meetingPoint: internalSettings.location, locationSharingEnabled: true)

            return FetchedMeetup(meetup: meetup, memberships: memberships)
        }
    }

    func addOrReload(meetupId: GroupId, teamId: GroupId) -> Promise<Meetup> {
        firstly { () -> Promise<Meetup> in
            if let meetup = try groupStorageManager.loadMeetup(meetupId) {
                logger.debug("Known meetup. Reloading.")
                return reload(meetup: meetup)
            } else {
                logger.debug("Unknown meetup. Adding.")
                guard let team = try groupStorageManager.loadTeam(teamId) else {
                    throw MeetupManagerError.didNotFindGroup
                }
                let teamMembership = try groupStorageManager.loadMembership(userId: signedInUser.userId, groupId: teamId)
                return firstly {
                    fetchMeetup(groupId: meetupId, decryptionKey: .parentKey(team.groupKey), serverSignedMembershipCertificate: teamMembership.serverSignedMembershipCertificate, groupTag: nil)
                }.map { fetchedGroup in
                    try self.groupStorageManager.storeMeetup(fetchedGroup.meetup)
                    try self.groupStorageManager.store(fetchedGroup.memberships, for: meetupId)
                    
                    return fetchedGroup.meetup
                }
            }
        }
    }

    func reload(meetup: Meetup) -> Promise<Meetup> {
        logger.debug("Reloading meetup \(meetup.groupId).")

        return firstly { () -> Promise<FetchedMeetup> in
            let membership: Membership
            if try groupStorageManager.isMember(userId: signedInUser.userId, groupId: meetup.groupId) {
                membership = try groupStorageManager.loadMembership(userId: signedInUser.userId, groupId: meetup.groupId)
            } else {
                membership = try groupStorageManager.loadMembership(userId: signedInUser.userId, groupId: meetup.teamId)
            }
            return fetchMeetup(groupId: meetup.groupId, decryptionKey: .meetupKey(meetup.groupKey), serverSignedMembershipCertificate: membership.serverSignedMembershipCertificate, groupTag: meetup.tag)
        }.map { fetchedGroup -> Meetup in
            var fetchedGroup = fetchedGroup
            fetchedGroup.meetup.locationSharingEnabled = meetup.locationSharingEnabled
            
            try self.groupStorageManager.storeMeetup(fetchedGroup.meetup)
            try self.groupStorageManager.store(fetchedGroup.memberships, for: meetup.groupId)

            return fetchedGroup.meetup
        }.recover { error -> Promise<Meetup> in
            if case BackendError.notModified = error {
                logger.debug("Meetup not modified.")
                return .value(meetup)
            }
            if let apiError = error as? APIError,
                case APIError.ErrorType.notFound = apiError.type {
                logger.info("Meetup \(meetup.groupId) not found. Removing meetup.")
                try self.groupStorageManager.removeMeetup(meetup: meetup)
            }
            if case BackendError.unauthorized = error {
                logger.info("User not member of meetup \(meetup.groupId). Removing meetup.")
                try self.groupStorageManager.removeMeetup(meetup: meetup)
            }
            throw error
        }
    }

    func join(_ meetup: Meetup) -> Promise<Void> {
        return firstly { () -> Promise<JoinGroupResponse> in
            let selfSignedMembershipCertificate = try authManager.createUserSignedMembershipCertificate(userId: signedInUser.userId, groupId: meetup.groupId, admin: false, issuerUserId: signedInUser.userId, signingKey: signedInUser.privateSigningKey)
            return backend.joinGroup(groupId: meetup.groupId, selfSignedMembershipCertificate: selfSignedMembershipCertificate, serverSignedAdminCertificate: nil, adminSignedMembershipCertificate: nil, groupTag: meetup.tag)
        }.then { joinGroupResponse in
            self.groupManager.addUserMember(into: meetup, admin: false, serverSignedMembershipCertificate: joinGroupResponse.serverSignedMembershipCertificate)
        }.done { membership, groupTag in
            try self.groupStorageManager.store(membership)
            try self.groupStorageManager.updateMeetupTag(groupId: meetup.groupId, tag: groupTag)

            self.resetReloadTimeout(groupId: meetup.groupId)
        }
    }

    func leave(_ meetup: Meetup) -> Promise<Void> {
        firstly {
            groupManager.leave(meetup)
        }.done { groupTag in
            try self.groupStorageManager.removeMembership(userId: self.signedInUser.userId, groupId: meetup.groupId, updatedGroupTag: groupTag)
        }
    }
    
    func adminMembership(meetup: Meetup) throws -> Membership {
        let teamMembership = try? groupStorageManager.loadMembership(userId: signedInUser.userId, groupId: meetup.teamId)
        let meetupMembership = try? groupStorageManager.loadMembership(userId: signedInUser.userId, groupId: meetup.groupId)

        if let meetupMembership = meetupMembership, meetupMembership.admin {
            return meetupMembership
        } else if let teamMembership = teamMembership, teamMembership.admin {
            return teamMembership
        } else {
            throw MeetupManagerError.permissionDenied
        }
    }

    func delete(_ meetup: Meetup) -> Promise<Void> {
        firstly { () -> Promise<Team> in
            let team = try self.groupStorageManager.teamOf(meetup: meetup)
            return firstly { () -> Promise<Void> in
                let adminMembership = try self.adminMembership(meetup: meetup)
                let otherMemberships = try groupStorageManager.loadMemberships(groupId: meetup.groupId).filter { $0.userId != signedInUser.userId }
                let notificationRecipients = otherMemberships.map { NotificationRecipient(userId: $0.userId, serverSignedMembershipCertificate: $0.serverSignedMembershipCertificate, priority: .alert) }
                return backend.deleteGroup(groupId: meetup.groupId, serverSignedAdminCertificate: adminMembership.serverSignedMembershipCertificate, groupTag: meetup.tag, notificationRecipients: notificationRecipients)
            }.then { _ -> Promise<Void> in
                try self.groupStorageManager.removeMeetup(meetup: meetup)
                return self.groupManager.sendGroupUpdateNotification(to: team, action: .childGroupDeleted)
            }.map { team }
        }.then { team -> Promise<Void> in
            guard let teamReloader = self.teamReloader else {
                logger.error("Team reloader not set.")
                return Promise()
            }
            return teamReloader.reload(team: team)
        }
    }

    func deleteGroupMember(_ membership: Membership, from meetup: Meetup) -> Promise<Void> {
        firstly { () -> Promise<Void> in
            let adminMembership = try self.adminMembership(meetup: meetup)
            return groupManager.deleteGroupMember(membership, from: meetup, serverSignedMembershipCertificate: adminMembership.serverSignedMembershipCertificate)
        }
    }

    func set(meetingPoint: CLLocationCoordinate2D?, in meetup: Meetup) -> Promise<Void> {
        let meetingPoint = meetingPoint.map { Location(latitude: $0.latitude, longitude: $0.longitude) }

        let internalSettings = InternalMeetupSettings(location: meetingPoint)

        return firstly { () -> Promise<UpdatedEtagResponse> in
            let membership = try groupStorageManager.loadMembership(userId: signedInUser.userId, groupId: meetup.groupId)

            let internalSettingsData = try encoder.encode(internalSettings)
            let encryptedInternalSettings = try cryptoManager.encrypt(internalSettingsData, secretKey: meetup.groupKey)

            let notificationRecipients = try groupManager.notificationRecipients(groupId: meetup.groupId, alert: true)

            return backend.updateInternalSettings(groupId: meetup.groupId, encryptedInternalSettings: encryptedInternalSettings, serverSignedMembershipCertificate: membership.serverSignedMembershipCertificate, groupTag: meetup.tag, notificationRecipients: notificationRecipients)
        }.done { updatedEtagResponse in
            try self.groupStorageManager.updateMeetingPoint(groupId: meetup.groupId, meetingPoint: meetingPoint, tag: updatedEtagResponse.groupTag)
        }
    }

    func sendLocationUpdate(location: Location) -> Promise<Void> {
        firstly { () -> Promise<Void> in
            let payloadContainer = PayloadContainer(payloadType: .locationUpdateV1, payload: LocationUpdate(location: location))
            let activeMeetups: [Meetup] = try groupStorageManager.loadMeetups().filter {
                try groupStorageManager.isMember(userId: signedInUser.userId, groupId: $0.groupId)
            }

            let locationUpdatePromises = activeMeetups.map { meetup -> Promise<Void> in
                return firstly { () -> Promise<Void> in
                    if !self.reloadTimeouts.keys.contains(meetup.groupId) {
                        self.resetReloadTimeout(groupId: meetup.groupId)
                    }

                    if let timeout = self.reloadTimeouts[meetup.groupId],
                        timeout < Date() {
                        return reload(meetup: meetup).done { reloadedMeetup in
                            logger.debug("Reload timer expired. Reloading meetup.")
                            if reloadedMeetup.tag != meetup.tag {
                                logger.warning("Meetup \(meetup.groupId) has been modified. We might have missed an update.")
                                self.tracker.log(action: .missedMeetupUpdate, category: .app)
                            }
                            self.resetReloadTimeout(groupId: meetup.groupId)
                        }
                    } else {
                        return .value(())
                    }
                }.then { () -> Promise<Void> in
                    self.groupManager.send(payloadContainer: payloadContainer, to: meetup, collapseId: .locationUpdate, priority: .deferred)
                }.recover { error in
                    logger.error("Failed to send location update to group \(meetup.groupId). Reason: \(error)")
                    throw error
                }
            }

            return when(resolved: locationUpdatePromises).asVoid()
        }
    }

    private func resetReloadTimeout(groupId: GroupId) {
        reloadTimeouts[groupId] = Date().addingTimeInterval(reloadTimeout)
    }
}

extension MeetupManager: LocationManagerDelegate {
    func processLocationUpdate(location: Location) {
        firstly {
            sendLocationUpdate(location: location)
        }.catch { error in
            logger.error("Sending location update failed: \(error)")
        }
    }
}
