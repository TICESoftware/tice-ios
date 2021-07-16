//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import CoreLocation
import Contacts

class MeetingPointAnnotation: Annotation {
    
    init(addressLocalizer: AddressLocalizerType, location: CLLocation) {
        super.init(location: location, addressLocalizer: addressLocalizer)
        self.title = L10n.Map.Location.meetingPoint
    }
    
    override func update() {
        subtitle = addressLocalizer.short(annotation: self)
    }
}
