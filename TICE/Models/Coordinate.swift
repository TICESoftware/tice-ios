//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import CoreLocation

struct Coordinate: Codable, Hashable {
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
}

extension CLLocationCoordinate2D {
    init(_ coordinate: Coordinate) {
        self = .init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

extension Coordinate {
    init(_ coordinate: CLLocationCoordinate2D) {
        self = .init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
