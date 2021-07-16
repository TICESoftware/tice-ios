//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels

protocol LocationStorageManagerType: DeletableStorageManagerType {
    func store(lastLocation: Location?) throws
    func loadLastLocation() throws -> Location?
    
    func locationRequired(userId: UserId) throws -> Bool
    func observeLocationRequirement(userId: UserId, queue: DispatchQueue, onChange: @escaping (Bool) -> Void) -> ObserverToken
    
    func locationSharingStates() throws -> [LocationSharingState]
    func locationSharingStates(withEnabledState enabled: Bool) throws -> [LocationSharingState]
    
    func locationSharingState(userId: UserId) throws -> [LocationSharingState]
    func locationSharingState(userId: UserId, groupId: GroupId) throws -> LocationSharingState?
    
    func observeLocationSharingState(queue: DispatchQueue, onChange: @escaping ([LocationSharingState]) -> Void) -> ObserverToken
    func observeLocationSharingState(groupId: GroupId, queue: DispatchQueue, onChange: @escaping ([LocationSharingState]) -> Void) -> ObserverToken
    func observeLocationSharingState(userId: UserId, groupId: GroupId, queue: DispatchQueue, onChange: @escaping (LocationSharingState?) -> Void) -> ObserverToken
    
    func othersLocationSharingState(ownUserId: UserId, groupId: GroupId) throws -> [LocationSharingState]
    func observeOthersLocationSharingState(ownUserId: UserId, groupId: GroupId, queue: DispatchQueue, onChange: @escaping ([LocationSharingState]) -> Void) -> ObserverToken

    func storeLocationSharingState(userId: UserId, groupId: GroupId, enabled: Bool, lastUpdated: Date) throws
}
