//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import CoreLocation

protocol CLLocationManagerType: AnyObject {
    var delegate: CLLocationManagerDelegate? { get set }
    var allowsBackgroundLocationUpdates: Bool { get set }
    var desiredAccuracy: CLLocationAccuracy { get set }
    var distanceFilter: CLLocationDistance { get set }
    var location: CLLocation? { get }

    func requestWhenInUseAuthorization()
    func startUpdatingLocation()
    func stopUpdatingLocation()

    func authorizationStatus() -> CLAuthorizationStatus
    func locationServicesEnabled() -> Bool
}
