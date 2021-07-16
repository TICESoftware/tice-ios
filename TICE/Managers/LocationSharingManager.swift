//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels
import PromiseKit
import UIKit

class LocationSharingManager: LocationSharingManagerType {
    
    struct UserGroupIds: Hashable {
        let userId: UserId
        let groupId: GroupId
    }
    
    let locationStorageManager: LocationStorageManagerType
    let groupManager: GroupManagerType
    let groupStorageManager: GroupStorageManagerType
    let userManager: UserManagerType
    let signedInUser: SignedInUser
    let notifier: Notifier
    
    weak var postOffice: PostOfficeType?
    
    let checkTime: TimeInterval
    let locationMaxAge: TimeInterval
    @SynchronizedProperty var lastLocations: [UserGroupIds: Location]
    var outdatedLocationSharingStateTimer: Timer?
    
    init(locationStorageManager: LocationStorageManagerType, groupManager: GroupManagerType, groupStorageManager: GroupStorageManagerType, userManager: UserManagerType, signedInUser: SignedInUser, postOffice: PostOfficeType, notifier: Notifier, checkTime: TimeInterval, locationMaxAge: TimeInterval) {
        self.locationStorageManager = locationStorageManager
        self.groupManager = groupManager
        self.groupStorageManager = groupStorageManager
        self.userManager = userManager
        self.signedInUser = signedInUser
        self.postOffice = postOffice
        self.notifier = notifier
        
        self.checkTime = checkTime
        self.locationMaxAge = locationMaxAge
        
        self.lastLocations = [:]
    }
    
    func registerHandler() {
        self.postOffice?.handlers[.locationUpdateV2] = { [unowned self] in
            self.handleLocationUpdate(payload: $0, metaInfo: $1, completion: $2)
        }
        DispatchQueue.main.async {
            self.outdatedLocationSharingStateTimer?.invalidate()
            self.outdatedLocationSharingStateTimer = Timer.scheduledTimer(withTimeInterval: self.checkTime, repeats: true) { [unowned self] _ in
                self.checkOutdatedLocationSharingStates()
            }
        }
        
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            logger.debug("Deactivating observation of outdated location sharing states")
            self?.outdatedLocationSharingStateTimer?.invalidate()
        }
        
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            logger.debug("Activating observation of outdated location sharing states")
            self.outdatedLocationSharingStateTimer = Timer.scheduledTimer(withTimeInterval: self.checkTime, repeats: true) { [unowned self] _ in
                self.checkOutdatedLocationSharingStates()
            }
        }
    }
    
    deinit {
        outdatedLocationSharingStateTimer?.invalidate()
        outdatedLocationSharingStateTimer = nil
        postOffice?.handlers[.locationUpdateV2] = nil
    }
    
    func lastLocation(userId: UserId, groupId: GroupId) -> Location? {
        if userId == signedInUser.userId {
            logger.warning("Location sharing manager was asked for the location of the signed in user but location manager should be asked instead.")
        }
        return lastLocations[UserGroupIds(userId: userId, groupId: groupId)]
    }
    
    func checkOutdatedLocationSharingStates() {
        logger.debug("Checking outdated location sharing states")
        do {
            let enabledOtherLocationSharingStates = try self.locationStorageManager.locationSharingStates(withEnabledState: true).filter { $0.userId != signedInUser.userId }
            
            guard !enabledOtherLocationSharingStates.isEmpty else {
                logger.debug("Nothing to check as no one shares their location with us.")
                return
            }
            
            for state in enabledOtherLocationSharingStates where state.lastUpdated.timeIntervalSinceNow < -locationMaxAge {
                if let location = lastLocation(userId: state.userId, groupId: state.groupId) {
                    if location.timestamp.timeIntervalSinceNow < -locationMaxAge {
                        logger.warning("Did not receive a location update from this user since a while while their location state is enabled. Disabling it now.")
                        try? locationStorageManager.storeLocationSharingState(userId: state.userId, groupId: state.groupId, enabled: false, lastUpdated: max(state.lastUpdated, location.timestamp))
                    }
                } else {
                    logger.warning("Did not receive a location update from this user at all while their location state is enabled. Disabling it now.")
                    try? locationStorageManager.storeLocationSharingState(userId: state.userId, groupId: state.groupId, enabled: false, lastUpdated: state.lastUpdated)
                }
            }
        } catch {
            logger.warning("Could not check for outdated location sharing states. Reason: \(error)")
        }
    }
    
    func locationSharingStates(groupId: GroupId) -> [LocationSharingState] {
        return othersLocationSharingState(ownUserId: self.signedInUser.userId, groupId: groupId) + [locationSharingState(userId: self.signedInUser.userId, groupId: groupId)]
    }
    
    func locationSharingState(userId: UserId, groupId: GroupId) -> LocationSharingState {
        let disabledState = LocationSharingState(userId: userId, groupId: groupId, enabled: false, lastUpdated: .distantPast)
        do {
            guard try groupStorageManager.isMember(userId: userId, groupId: groupId) else {
                logger.warning("TeamManager was asked for locationSharingState of \(userId) in \(groupId), while the user is not a member of the group.")
                return disabledState
            }
            return try self.locationStorageManager.locationSharingState(userId: userId, groupId: groupId) ?? disabledState
        } catch {
            logger.warning("Location sharing state of user \(userId) in group \(groupId) could not be determined. Reason: \(error)")
            return disabledState
        }
    }
    
    func observeLocationSharingState(queue: DispatchQueue, onChange: @escaping ([LocationSharingState]) -> Void) -> ObserverToken {
        return locationStorageManager.observeLocationSharingState(queue: queue, onChange: onChange)
    }
    
    func observeLocationSharingState(userId: UserId, groupId: GroupId, queue: DispatchQueue, onChange: @escaping (LocationSharingState) -> Void) -> ObserverToken {
        return locationStorageManager.observeLocationSharingState(userId: userId, groupId: groupId, queue: queue, onChange: {
            onChange($0 ?? LocationSharingState(userId: userId, groupId: groupId, enabled: false, lastUpdated: Date()))
        })
    }
    
    func observeLocationSharingState(groupId: GroupId, queue: DispatchQueue, onChange: @escaping ([LocationSharingState]) -> Void) -> ObserverToken {
        return locationStorageManager.observeLocationSharingState(groupId: groupId, queue: queue) { knownStates in
            do {
                let members = try self.groupStorageManager.members(groupId: groupId)
                let knownStatesMap = [UserGroupIds: [LocationSharingState]](grouping: knownStates, by: { return UserGroupIds(userId: $0.userId, groupId: $0.groupId) }).compactMapValues { $0.first }
                let allStates = members.map {
                    return knownStatesMap[UserGroupIds(userId: $0.user.userId, groupId: $0.membership.groupId)] ?? LocationSharingState(userId: $0.user.userId, groupId: $0.membership.groupId, enabled: false, lastUpdated: .distantPast)
                }
                onChange(allStates)
            } catch {
                logger.warning("Observing others' location sharing state failed. Reason: \(error)")
            }
        }
    }
    
    func observeOthersLocationSharingState(groupId: GroupId, queue: DispatchQueue, onChange: @escaping ([LocationSharingState]) -> Void) -> ObserverToken {
        return locationStorageManager.observeOthersLocationSharingState(ownUserId: signedInUser.userId, groupId: groupId, queue: queue, onChange: { knownStates in
            do {
                let otherMembers = try self.groupStorageManager.members(groupId: groupId).filter { $0.user.userId != self.signedInUser.userId }
                let knownStatesMap = [UserGroupIds: [LocationSharingState]](grouping: knownStates, by: { return UserGroupIds(userId: $0.userId, groupId: $0.groupId) }).compactMapValues { $0.first }
                let allStates = otherMembers.map {
                    return knownStatesMap[UserGroupIds(userId: $0.user.userId, groupId: $0.membership.groupId)] ?? LocationSharingState(userId: $0.user.userId, groupId: $0.membership.groupId, enabled: false, lastUpdated: .distantPast)
                }
                onChange(allStates)
            } catch {
                logger.warning("Observing others' location sharing state failed. Reason: \(error)")
            }
        })
    }
    
    func othersLocationSharingState(ownUserId: UserId, groupId: GroupId) -> [LocationSharingState] {
        do {
            let otherMembers = try groupStorageManager.members(groupId: groupId).filter { $0.user.userId != ownUserId }
            let knownStates = try locationStorageManager.othersLocationSharingState(ownUserId: ownUserId, groupId: groupId)
            let knownStatesMap = [UserGroupIds: [LocationSharingState]](grouping: knownStates, by: { return UserGroupIds(userId: $0.userId, groupId: $0.groupId) }).compactMapValues { $0.first }
            return otherMembers.map {
                return knownStatesMap[UserGroupIds(userId: $0.user.userId, groupId: $0.membership.groupId)] ??
                    LocationSharingState(userId: $0.user.userId, groupId: $0.membership.groupId, enabled: false, lastUpdated: .distantPast)
            }
        } catch {
            logger.warning("Location sharing state of other users in group \(groupId) could not be determined. Reason: \(error)")
            return []
        }
    }
    
    func handleLocationUpdate(payload: Payload, metaInfo: PayloadMetaInfo, completion: PostOfficeType.PayloadHandler?) {
        guard let locationUpdate = payload as? LocationUpdateV2 else {
            logger.error("Invalid payload type. Expected location update.")
            completion?(.failed)
            return
        }
        
        guard let user = userManager.user(metaInfo.senderId) else {
            logger.error("Unknown user for location update.")
            completion?(.failed)
            return
        }
        
        guard (try? groupStorageManager.isMember(userId: metaInfo.senderId, groupId: locationUpdate.groupId)) == true else {
            logger.error("User \(user.userId) is not in group \(locationUpdate.groupId) for location update.")
            completion?(.failed)
            return
        }
        
        var location = locationUpdate.location
        if location.timestamp.timeIntervalSinceNow > 0 {
            logger.warning("Location update from \(user) is in the future: \(location.timestamp). Overwriting date with now.")
            location.timestamp = Date()
        }
        
        let key = UserGroupIds(userId: user.userId, groupId: locationUpdate.groupId)
        let neverHadLocationOrLastLocationIsOlder = lastLocations[key] == nil || lastLocations[key]!.timestamp < location.timestamp
        guard neverHadLocationOrLastLocationIsOlder else {
            logger.debug("This location update is older than last location update. Skipping it.")
            completion?(.noData)
            return
        }
        
        lastLocations[key] = location
        logger.debug("Location for user \(user.userId) updated.")
        
        let locationSharingState = locationSharingState(userId: metaInfo.senderId, groupId: locationUpdate.groupId)
        if !locationSharingState.enabled {
            logger.debug("Received location update from user \(user.userId) but their location sharing state was disabled at \(locationSharingState.lastUpdated).")
            
            let locationUpdateRecentEnough = -location.timestamp.timeIntervalSinceNow <= locationMaxAge
            if locationSharingState.lastUpdated < location.timestamp && locationUpdateRecentEnough {
                do {
                    logger.warning("Enabling location sharing for user \(user.userId) now.")
                    try locationStorageManager.storeLocationSharingState(userId: user.userId, groupId: locationUpdate.groupId, enabled: true, lastUpdated: location.timestamp)
                } catch {
                    logger.warning("Could not enable location sharing state for user \(user.userId) in group \(locationUpdate.groupId). Reason: \(String(describing: error))")
                }
            } else {
                logger.debug("Location update was before location sharing was last disabled or is too old. Not enabling location sharing for this user.")
            }
        }
        
        notifier.notify(UserLocationUpdateNotificationHandler.self) { $0.didUpdateLocation(userId: user.userId) }
        
        completion?(.newData)
    }
    
    func storeLocationSharingState(userId: UserId, groupId: GroupId, enabled: Bool, lastUpdated: Date) throws {
        try locationStorageManager.storeLocationSharingState(userId: userId, groupId: groupId, enabled: enabled, lastUpdated: lastUpdated)
    }
}
