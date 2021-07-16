//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import CoreLocation

extension CLLocationManager: CLLocationManagerType {
    func authorizationStatus() -> CLAuthorizationStatus { CLLocationManager.authorizationStatus() }
    func locationServicesEnabled() -> Bool { CLLocationManager.locationServicesEnabled() }
}
