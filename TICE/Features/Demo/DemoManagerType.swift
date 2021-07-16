//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import CoreLocation
import TICEAPIModels
import class Observable.Observable

protocol DemoManagerType: AnyObject {
    
    var isDemoEnabled: Bool { get }
    
    var demoTeam: Observable<DemoTeam> { get }
    var showMeetupButton: Observable<Bool> { get }
    var locationSharingStates: Observable<[LocationSharingState]> { get }
    
    var messages: [DemoMessage] { get }
    var memberLocations: Set<MemberLocation> { get }
    var teamAvatar: UIImage { get }
    var lastLocation: Coordinate? { get set }
    
    func demoUser(userId: UserId) -> DemoUser?
    func lastLocation(userId: UserId) -> Location?
    
    func avatar(demoUser: DemoUser) -> UIImage
    
    func didRegister()
    
    func didOpenTeam()
    func didCloseTeam()
    
    func didOpenChat()
    func didCloseChat()
    
    func didStartLocationSharing()
    func didEndLocationSharing()
    
    func didOpenTeamSettings()
    
    func didMarkLocation()
    func didHideAnnotation()
    
    func didCreateMeetingPoint(location: CLLocationCoordinate2D)
    func didDeleteMeetingPoint()
    
    func didSelectUser(user: DemoUser)
    
    func resetDemo()
    func endDemo()
}
