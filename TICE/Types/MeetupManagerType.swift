//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import CoreLocation
import PromiseKit
import TICEAPIModels

protocol MeetupManagerType: AnyObject {
    var teamReloader: TeamReloader? { get set }
    
    func createMeetup(in team: Team, at location: Location?, joinMode: JoinMode, permissionMode: PermissionMode) -> Promise<Meetup>
    func join(_ meetup: Meetup) -> Promise<Void>
    func leave(_ meetup: Meetup) -> Promise<Void>
    func delete(_ meetup: Meetup) -> Promise<Void>
    func deleteGroupMember(_ membership: Membership, from meetup: Meetup) -> Promise<Void>
    func set(meetingPoint: CLLocationCoordinate2D?, in meetup: Meetup) -> Promise<Void>
    func sendLocationUpdate(location: Location) -> Promise<Void>

    func reload(meetup: Meetup) -> Promise<Meetup>
    func addOrReload(meetupId: GroupId, teamId: GroupId) -> Promise<Meetup>
}
