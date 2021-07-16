//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels
import PromiseKit
import CoreLocation

protocol TeamManagerType {
    var teams: [Team] { get }
    
    func setup()

    func teamWith(groupId: GroupId) -> Team?
    func createTeam(joinMode: JoinMode, permissionMode: PermissionMode, name: String?, shareLocation: Bool, meetingPoint: Location?) -> Promise<Team>
    func getOrFetchTeam(groupId: GroupId, groupKey: SecretKey) -> Promise<Team>
    func join(_ team: Team) -> Promise<Team>
    func leave(_ team: Team) -> Promise<Void>
    func delete(_ team: Team) -> Promise<Void>
    func deleteGroupMember(_ membership: Membership, from team: Team) -> Promise<Void>
    func reload(team: Team, reloadMeetup: Bool) -> Promise<Team>
    func reloadAllTeams() -> Promise<Void>

    func setTeamName(team: Team, name: String?) -> Promise<Void>
    func set(meetingPoint: CLLocationCoordinate2D?, in team: Team) -> Promise<Void>
    func setLocationSharing(in team: Team, enabled: Bool) -> Promise<Void>
}
