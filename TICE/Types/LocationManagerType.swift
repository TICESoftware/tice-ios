//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import CoreLocation
import TICEAPIModels

protocol LocationManagerType: AnyObject {
    var delegate: LocationManagerDelegate? { get set }

    var lastUserLocation: Location? { get }
    var currentUserLocation: Location? { get }

    func setup()

    var authorizationStatus: LocationAuthorizationStatus { get }
    var notAuthorizedToUseLocation: Bool { get }

    func requestLocationAuthorization()
}
