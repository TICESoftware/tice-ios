//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import CoreLocation
import MapKit

extension Array where Element == CLLocationCoordinate2D {
    func makeRect() -> MKMapRect? {
        guard !isEmpty else { return nil }
        
        let first = first!
        let top = reduce(first.latitude) { Swift.max($0, $1.latitude) }
        let left = reduce(first.longitude) { Swift.min($0, $1.longitude) }
        let bottom = reduce(first.latitude) { Swift.min($0, $1.latitude) }
        let right = reduce(first.longitude) { Swift.max($0, $1.longitude) }
        
        let topLeft = MKMapPoint(CLLocationCoordinate2D(latitude: top, longitude: left))
        let bottomRight = MKMapPoint(CLLocationCoordinate2D(latitude: bottom, longitude: right))
        
        return MKMapRect(x: topLeft.x,
                         y: topLeft.y,
                         width: bottomRight.x - topLeft.x,
                         height: bottomRight.y - topLeft.y)
    }
}
