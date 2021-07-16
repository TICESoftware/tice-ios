//
//  Copyright © 2018 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels
import ConvAPI
import PromiseKit
import CoreLocation

enum TeamManagerError: LocalizedError {
    case userAlreadyMember
    case notMember
    case notAdmin
    case meetupExisting
    case notAuthorizedToUseLocation

    var errorDescription: String? {
        switch self {
        case .userAlreadyMember: return L10n.Error.TeamManager.userAlreadyMember
        case .notMember: return L10n.Error.TeamManager.notMember
        case .notAdmin: return L10n.Error.TeamManager.notAdmin
        case .meetupExisting: return L10n.Error.TeamManager.meetupExisting
        case .notAuthorizedToUseLocation: return L10n.Error.TeamManager.notAuthorizedToUseLocation
        }
    }
}

protocol TeamReloader: AnyObject {
    func reload(team: Team) -> Promise<Void>
}

class TeamManager: TeamManagerType, TeamReloader {
    let groupManager: GroupManagerType
    let meetupManager: MeetupManagerType
    let groupStorageManager: GroupStorageManagerType
    let signedInUser: SignedInUser
    let cryptoManager: CryptoManagerType
    let authManager: AuthManagerType
    let userManager: UserManagerType
    let locationManager: LocationManagerType
    let locationStorageManager: LocationStorageManagerType
    let backend: TICEAPI
    let encoder: JSONEncoder
    let decoder: JSONDecoder

    var teams: [Team] {
        do {
            return try groupStorageManager.loadTeams()
        } catch {
            logger.error("Failed to load teams: \(String(describing: error))")
            return []
        }
    }

    init(groupManager: GroupManagerType, meetupManager: MeetupManagerType, groupStorageManager: GroupStorageManagerType, signedInUser: SignedInUser, cryptoManager: CryptoManagerType, authManager: AuthManagerType, userManager: UserManagerType, locationManager: LocationManagerType, locationStorageManager: LocationStorageManagerType, backend: TICEAPI, mailbox: MailboxType, encoder: JSONEncoder, decoder: JSONDecoder) {
        self.groupManager = groupManager
        self.meetupManager = meetupManager
        self.groupStorageManager = groupStorageManager
        self.signedInUser = signedInUser
        self.cryptoManager = cryptoManager
        self.authManager = authManager
        self.userManager = userManager
        self.locationManager = locationManager
        self.locationStorageManager = locationStorageManager
        self.backend = backend
        self.encoder = encoder
        self.decoder = decoder
    }
    
    func setup() {
        meetupManager.teamReloader = self
        locationManager.delegate = self
    }

    func teamWith(groupId: GroupId) -> Team? {
        do {
            return try groupStorageManager.loadTeam(groupId)
        } catch {
            logger.error("Failed to load team: \(String(describing: error))")
            return nil
        }
    }

    func createTeam(joinMode: JoinMode, permissionMode: PermissionMode, name: String?, shareLocation: Bool, meetingPoint: Location?) -> Promise<Team> {
        let groupId = GroupId()
        let groupKey = cryptoManager.generateGroupKey()
        
        return firstly { () -> Promise<CreateGroupResponse> in
            let groupSettings = GroupSettings(owner: signedInUser.userId, name: name)
            let groupSettingsData = try encoder.encode(groupSettings)

            let internalTeamSettings = InternalTeamSettings(meetingPoint: meetingPoint)
            let internalTeamSettingsData = try encoder.encode(internalTeamSettings)

            let encryptedGroupSettings = try cryptoManager.encrypt(groupSettingsData, secretKey: groupKey)
            let encryptedInternalSettings = try cryptoManager.encrypt(internalTeamSettingsData, secretKey: groupKey)

            let selfSignedAdminCertificate = try authManager.createUserSignedMembershipCertificate(userId: signedInUser.userId, groupId: groupId, admin: true, issuerUserId: signedInUser.userId, signingKey: signedInUser.privateSigningKey)

            return backend.createGroup(userId: signedInUser.userId,
                                       type: .team,
                                       joinMode: joinMode,
                                       permissionMode: permissionMode,
                                       groupId: groupId,
                                       parentGroup: nil,
                                       selfSignedAdminCertificate: selfSignedAdminCertificate,
                                       encryptedSettings: encryptedGroupSettings,
                                       encryptedInternalSettings: encryptedInternalSettings)
        }.then { createGroupResponse -> Promise<Team> in
            let team = Team(groupId: groupId, groupKey: groupKey, owner: self.signedInUser.userId, joinMode: joinMode, permissionMode: permissionMode, tag: createGroupResponse.groupTag, url: createGroupResponse.url, name: name, meetupId: nil, meetingPoint: meetingPoint)
            try self.groupStorageManager.storeTeam(team)
            try self.locationStorageManager.storeLocationSharingState(userId: self.signedInUser.userId, groupId: groupId, enabled: shareLocation, lastUpdated: Date())
            
            return firstly {
                self.groupManager.addUserMember(into: team, admin: true, serverSignedMembershipCertificate: createGroupResponse.serverSignedAdminCertificate)
            }.map { membership, updatedEtag -> Team in
                try self.groupStorageManager.store(membership)
                try self.groupStorageManager.updateTeamTag(groupId: groupId, tag: updatedEtag)

                return team
            }
        }
    }

    private struct FetchedTeam {
        let team: Team
        let memberships: [Membership]
    }

    private func fetchTeam(groupId: GroupId, groupKey: SecretKey, serverSignedMembershipCertificate: Certificate, groupTag: GroupTag?) -> Promise<FetchedTeam> {
        return firstly {
            backend.getGroupInternals(groupId: groupId, serverSignedMembershipCertificate: serverSignedMembershipCertificate, groupTag: groupTag)
        }.then { groupInternalsResponse -> Promise<FetchedTeam> in
            let settingsPlaintext = try self.cryptoManager.decrypt(encryptedData: groupInternalsResponse.encryptedSettings, secretKey: groupKey)
            let settings = try self.decoder.decode(GroupSettings.self, from: settingsPlaintext)
            
            let internalSettingsPlaintext = try self.cryptoManager.decrypt(encryptedData: groupInternalsResponse.encryptedInternalSettings, secretKey: groupKey)
            let internalSettings = try self.decoder.decode(InternalTeamSettings.self, from: internalSettingsPlaintext)

            let memberships = try groupInternalsResponse.encryptedMemberships.map { encryptedMembership -> Membership in
                let membershipPlaintext = try self.cryptoManager.decrypt(encryptedData: encryptedMembership, secretKey: groupKey)
                return try self.decoder.decode(Membership.self, from: membershipPlaintext)
            }

            let team = Team(groupId: groupId, groupKey: groupKey, owner: settings.owner, joinMode: groupInternalsResponse.joinMode, permissionMode: groupInternalsResponse.permissionMode, tag: groupInternalsResponse.groupTag, url: groupInternalsResponse.url, name: settings.name, meetupId: groupInternalsResponse.children.first, meetingPoint: internalSettings.meetingPoint)

            let fetchedTeam = FetchedTeam(team: team, memberships: memberships)

            let userPromises = memberships.map { self.userManager.getUser($0.userId).asVoid() }
            return when(fulfilled: userPromises).map { fetchedTeam }
        }
    }
    
    func reload(team: Team) -> Promise<Void> {
        reload(team: team, reloadMeetup: false).asVoid()
    }

    func reload(team: Team, reloadMeetup: Bool) -> Promise<Team> {
        logger.debug("Reloading team \(team.groupId).")

        return firstly { () -> Promise<FetchedTeam> in
            guard try groupStorageManager.isMember(userId: signedInUser.userId, groupId: team.groupId) else {
                throw TeamManagerError.notMember
            }

            let membership = try groupStorageManager.loadMembership(userId: signedInUser.userId, groupId: team.groupId)
            return fetchTeam(groupId: team.groupId, groupKey: team.groupKey, serverSignedMembershipCertificate: membership.serverSignedMembershipCertificate, groupTag: team.tag)
        }.map { fetchedGroup in
            try self.groupStorageManager.storeTeam(fetchedGroup.team)
            try self.groupStorageManager.store(fetchedGroup.memberships, for: team.groupId)

            return fetchedGroup.team
        }.recover { error -> Promise<Team> in
            if case BackendError.notModified = error {
                logger.debug("Team not modified.")
                return .value(team)
            }
            if let apiError = error as? APIError,
                case APIError.ErrorType.notFound = apiError.type {
                logger.info("Team \(team.groupId) not found. Removing team.")
                try self.groupStorageManager.removeTeam(team.groupId)
            }
            if case BackendError.unauthorized = error {
                logger.info("User not member of team \(team.groupId). Removing team.")
                try self.groupStorageManager.removeTeam(team.groupId)
            }
            throw error
        }.then { team -> Promise<Team> in
            guard reloadMeetup,
                  let meetupId = team.meetupId else {
                return .value(team)
            }
            return self.meetupManager.addOrReload(meetupId: meetupId, teamId: team.groupId).map { _ in team }
        }
    }

    func reloadAllTeams() -> Promise<Void> {
        firstly { () -> Promise<Void> in
            let reloadPromises = try groupStorageManager.loadTeams().map { reload(team: $0, reloadMeetup: true).asVoid() }
            return when(resolved: reloadPromises).asVoid()
        }
    }

    func getOrFetchTeam(groupId: GroupId, groupKey: SecretKey) -> Promise<Team> {
        return firstly { () -> Promise<Team> in
            if let team = try groupStorageManager.loadTeam(groupId) {
                return .value(team)
            }
            return firstly {
                backend.getGroupInformation(groupId: groupId, groupTag: nil)
            }.map { groupInformationResponse -> Team in
                let groupSettingsPlaintext = try self.cryptoManager.decrypt(encryptedData: groupInformationResponse.encryptedSettings, secretKey: groupKey)
                let groupSettings: GroupSettings = try self.decoder.decode(GroupSettings.self, from: groupSettingsPlaintext)

                let team = Team(groupId: groupInformationResponse.groupId, groupKey: groupKey, owner: groupSettings.owner, joinMode: groupInformationResponse.joinMode, permissionMode: groupInformationResponse.permissionMode, tag: groupInformationResponse.groupTag, url: groupInformationResponse.url, name: groupSettings.name, meetupId: nil)

                return team
            }
        }
    }

    func join(_ team: Team) -> Promise<Team> {
        return firstly { () -> Promise<JoinGroupResponse> in
            guard try !groupStorageManager.isMember(userId: signedInUser.userId, groupId: team.groupId) else {
                throw TeamManagerError.userAlreadyMember
            }

            let selfSignedMembershipCertificate = try authManager.createUserSignedMembershipCertificate(userId: signedInUser.userId, groupId: team.groupId, admin: false, issuerUserId: signedInUser.userId, signingKey: signedInUser.privateSigningKey)
            return backend.joinGroup(groupId: team.groupId, selfSignedMembershipCertificate: selfSignedMembershipCertificate, serverSignedAdminCertificate: nil, adminSignedMembershipCertificate: nil, groupTag: team.tag)
        }.then { joinGroupResponse -> Promise<Team> in
            firstly {
                self.fetchTeam(groupId: team.groupId, groupKey: team.groupKey, serverSignedMembershipCertificate: joinGroupResponse.serverSignedMembershipCertificate, groupTag: nil)
            }.then { fetchedTeam -> Promise<Team> in
                try self.groupStorageManager.storeTeam(fetchedTeam.team)
                try self.groupStorageManager.store(fetchedTeam.memberships, for: team.groupId)

                return firstly {
                    self.groupManager.addUserMember(into: fetchedTeam.team, admin: false, serverSignedMembershipCertificate: joinGroupResponse.serverSignedMembershipCertificate)
                }.map { membership, updatedEtag -> Team in
                    try self.groupStorageManager.store(membership)
                    try self.groupStorageManager.updateTeamTag(groupId: team.groupId, tag: updatedEtag)

                    var updatedTeam = fetchedTeam.team
                    updatedTeam.tag = updatedEtag
                    return updatedTeam
                }
            }
        }.then { team -> Promise<Team> in
            if let meetupId = team.meetupId {
                return self.meetupManager.addOrReload(meetupId: meetupId, teamId: team.groupId).map { _ in team }
            } else {
                return .value(team)
            }
        }
    }

    func leave(_ team: Team) -> Promise<Void> {
        firstly { () -> Promise<Void> in
            if let meetup = try groupStorageManager.meetupIn(team: team),
                try groupStorageManager.isMember(userId: signedInUser.userId, groupId: meetup.groupId) {
                return groupManager.leave(meetup).asVoid()
            } else {
                return .value(())
            }
        }.then { () -> Promise<Void> in
            return self.groupManager.leave(team).asVoid()
        }.done { _ in
            try self.groupStorageManager.removeTeam(team.groupId)
        }
    }

    func delete(_ team: Team) -> Promise<Void> {
        firstly { () -> Promise<Void> in
            guard try groupStorageManager.meetupIn(team: team) == nil else {
                throw TeamManagerError.meetupExisting
            }
            let membership = try groupStorageManager.loadMembership(userId: signedInUser.userId, groupId: team.groupId)

            guard membership.admin else {
                throw TeamManagerError.notAdmin
            }

            let notificationRecipients = try groupManager.notificationRecipients(groupId: team.groupId, alert: true)
            return backend.deleteGroup(groupId: team.groupId, serverSignedAdminCertificate: membership.serverSignedMembershipCertificate, groupTag: team.tag, notificationRecipients: notificationRecipients)
        }.done {
            try self.groupStorageManager.removeTeam(team.groupId)
        }
    }

    func deleteGroupMember(_ membership: Membership, from team: Team) -> Promise<Void> {
        firstly { () -> Promise<Void> in
            let ownMembership = try groupStorageManager.loadMembership(userId: signedInUser.userId, groupId: team.groupId)

            guard ownMembership.admin else {
                throw TeamManagerError.notAdmin
            }

            return firstly { () -> Promise<Void> in
                if let meetup = try groupStorageManager.meetupIn(team: team),
                    try groupStorageManager.isMember(userId: membership.userId, groupId: team.groupId) {
                    let meetupMembership = try groupStorageManager.loadMembership(userId: membership.userId, groupId: meetup.groupId)
                    return groupManager.deleteGroupMember(meetupMembership, from: meetup, serverSignedMembershipCertificate: ownMembership.serverSignedMembershipCertificate)
                } else {
                    return .init()
                }
            }.then {
                self.groupManager.deleteGroupMember(membership, from: team, serverSignedMembershipCertificate: ownMembership.serverSignedMembershipCertificate)
            }
        }
    }

    func setTeamName(team: Team, name: String?) -> Promise<Void> {
        firstly { () -> Promise<UpdatedEtagResponse> in
            let settings = GroupSettings(owner: team.owner, name: name)
            let settingsData = try encoder.encode(settings)
            let encryptedSettings = try cryptoManager.encrypt(settingsData, secretKey: team.groupKey)

            let membership = try groupStorageManager.loadMembership(userId: signedInUser.userId, groupId: team.groupId)

            let notificationRecipients = try groupManager.notificationRecipients(groupId: team.groupId, alert: true)

            return backend.updateSettings(groupId: team.groupId, encryptedSettings: encryptedSettings, serverSignedMembershipCertificate: membership.serverSignedMembershipCertificate, groupTag: team.tag, notificationRecipients: notificationRecipients)
        }.done { updatedGroupResponse in
            try self.groupStorageManager.updateTeamName(groupId: team.groupId, name: name, tag: updatedGroupResponse.groupTag)
        }
    }
    
    func set(meetingPoint: CLLocationCoordinate2D?, in team: Team) -> Promise<Void> {
        let meetingPoint = meetingPoint.map { Location(latitude: $0.latitude, longitude: $0.longitude) }

        let internalSettings = InternalTeamSettings(meetingPoint: meetingPoint)

        return firstly { () -> Promise<UpdatedEtagResponse> in
            let membership = try groupStorageManager.loadMembership(userId: signedInUser.userId, groupId: team.groupId)

            let internalSettingsData = try encoder.encode(internalSettings)
            let encryptedInternalSettings = try cryptoManager.encrypt(internalSettingsData, secretKey: team.groupKey)

            let notificationRecipients = try groupManager.notificationRecipients(groupId: team.groupId, alert: true)

            return backend.updateInternalSettings(groupId: team.groupId, encryptedInternalSettings: encryptedInternalSettings, serverSignedMembershipCertificate: membership.serverSignedMembershipCertificate, groupTag: team.tag, notificationRecipients: notificationRecipients)
        }.done { updatedEtagResponse in
            try self.groupStorageManager.updateMeetingPoint(groupId: team.groupId, meetingPoint: meetingPoint, tag: updatedEtagResponse.groupTag)
        }
    }
    
    func setLocationSharing(in team: Team, enabled: Bool) -> Promise<Void> {
        return firstly { () -> Promise<Void> in
            if enabled && self.locationManager.notAuthorizedToUseLocation {
                logger.info("Cannot enable location sharing due to lack of authorization.")
                throw TeamManagerError.notAuthorizedToUseLocation
            }
            try locationStorageManager.storeLocationSharingState(userId: self.signedInUser.userId, groupId: team.groupId, enabled: enabled, lastUpdated: Date())
            return .value
        }.then { () -> Promise<Void> in
            let payloadContainer = PayloadContainer(payloadType: .locationSharingUpdateV1, payload: LocationSharingUpdate(groupId: team.groupId, sharingEnabled: enabled))
            return self.groupManager.send(payloadContainer: payloadContainer, to: team, collapseId: nil, priority: .alert)
        }
    }
}

extension TeamManager: TeamBroadcaster {
    func sendToAllTeams(payloadContainer: PayloadContainer) -> Promise<Void> {
        let teamsArray = Array(teams)

        return firstly { () -> Guarantee<[Result<Void>]> in
            let sendingPromises = teamsArray.map { groupManager.send(payloadContainer: payloadContainer, to: $0, collapseId: nil, priority: .background) }
            return when(resolved: sendingPromises)
        }.done { results in
            for (team, result) in zip(teamsArray, results) {
                if case .rejected(let error) = result {
                    logger.error("Could not send message to team \(team.groupId): \(String(describing: error)).")
                }
            }
        }
    }
    
    func sendLocationUpdate(location: Location) -> Promise<Void> {
        firstly { () -> Promise<Void> in
            
            let groupsWithLocationSharing = try locationStorageManager.locationSharingState(userId: signedInUser.userId).compactMap { state -> Team? in
                guard state.enabled else { return nil }
                return try groupStorageManager.loadTeam(state.groupId)
            }
            
            let locationUpdatePromises = groupsWithLocationSharing.map { team -> Promise<Void> in
                let payloadContainer = PayloadContainer(payloadType: .locationUpdateV2, payload: LocationUpdateV2(location: location, groupId: team.groupId))
                return firstly { () -> Promise<Void> in
                    self.groupManager.send(payloadContainer: payloadContainer, to: team, collapseId: .locationUpdate, priority: .deferred)
                }.recover { error in
                    logger.error("Failed to send location update to group \(team.groupId). Reason: \(error)")
                    throw error
                }
            }
            
            return when(resolved: locationUpdatePromises).asVoid()
        }
    }
}

extension TeamManager: LocationManagerDelegate {
    func processLocationUpdate(location: Location) {
        firstly {
            sendLocationUpdate(location: location)
        }.catch { error in
            logger.error("Sending location update failed: \(error)")
        }
    }
}
