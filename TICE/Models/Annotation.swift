//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import CoreLocation
import MapKit

public class Annotation: NSObject, MKAnnotation {

    let addressLocalizer: AddressLocalizerType
    
    public var attachedAccuracyCircle: MKCircle?
    public var titlePlaceholder: String?
    public var subtitlePlaceholder: String?

    public var location: CLLocation {
        didSet {
            coordinate = location.coordinate
            if location != oldValue {
                placemark = nil
            }
        }
    }

    public var placemark: CLPlacemark? {
        didSet {
            if placemark != oldValue {
                update()
            }
        }
    }

    // MARK: - MKAnnotation

    @objc public dynamic var coordinate: CLLocationCoordinate2D
    @objc public dynamic var title: String?
    @objc public dynamic var subtitle: String?

    // MARK: -

    init(location: CLLocation, addressLocalizer: AddressLocalizerType) {
        self.location = location
        self.coordinate = location.coordinate
        self.subtitle = subtitlePlaceholder
        self.addressLocalizer = addressLocalizer
        
        super.init()
        
        self.subtitlePlaceholder = addressLocalizer.short(annotation: self)
    }
    
    public func update() {
        
    }
}
