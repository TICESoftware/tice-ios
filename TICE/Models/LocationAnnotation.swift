//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import CoreLocation
import Contacts

public class LocationAnnotation: Annotation {
    
    convenience init(placemark: CLPlacemark, addressLocalizer: AddressLocalizerType) {
        self.init(location: placemark.location!, addressLocalizer: addressLocalizer)
        self.placemark = placemark
        self.title = placemark.name
    }
    
    override init(location: CLLocation, addressLocalizer: AddressLocalizerType) {
        super.init(location: location, addressLocalizer: addressLocalizer)
        
        self.titlePlaceholder = L10n.Map.Location.pin
        self.title = titlePlaceholder
    }
    
    override public func update() {
        subtitle = addressLocalizer.short(annotation: self)
    }
}
