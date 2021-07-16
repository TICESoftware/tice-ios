//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels
import GRDB

protocol LocationSharingManagerType: AnyObject {
    func registerHandler()
    func lastLocation(userId: UserId, groupId: GroupId) -> Location?
    
    func storeLocationSharingState(userId: UserId, groupId: GroupId, enabled: Bool, lastUpdated: Date) throws
    func locationSharingState(userId: UserId, groupId: GroupId) -> LocationSharingState
    func locationSharingStates(groupId: GroupId) -> [LocationSharingState]
    func othersLocationSharingState(ownUserId: UserId, groupId: GroupId) -> [LocationSharingState]
    
    func observeLocationSharingState(queue: DispatchQueue, onChange: @escaping ([LocationSharingState]) -> Void) -> ObserverToken
    func observeLocationSharingState(groupId: GroupId, queue: DispatchQueue, onChange: @escaping ([LocationSharingState]) -> Void) -> ObserverToken
    func observeLocationSharingState(userId: UserId, groupId: GroupId, queue: DispatchQueue, onChange: @escaping (LocationSharingState) -> Void) -> ObserverToken
    func observeOthersLocationSharingState(groupId: GroupId, queue: DispatchQueue, onChange: @escaping ([LocationSharingState]) -> Void) -> ObserverToken
}
