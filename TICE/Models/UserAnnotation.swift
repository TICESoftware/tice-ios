//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import CoreLocation

class DemoUserAnnotation: Annotation {
    
    let demoManager: DemoManagerType
    let user: DemoUser

    init(location: CLLocation, demoUser: DemoUser, demoManager: DemoManagerType, addressLocalizer: AddressLocalizerType) {
        self.demoManager = demoManager
        self.user = demoUser
        
        super.init(location: location, addressLocalizer: addressLocalizer)

        self.title = user.name
        self.subtitlePlaceholder = user.role
        self.accessibilityLabel = self.title
    }
}

class UserAnnotation: Annotation {
    
    let user: User
    let alwaysUpToDate: Bool

    init(location: CLLocation, user: User, alwaysUpToDate: Bool, nameSupplier: NameSupplierType, addressLocalizer: AddressLocalizerType) {
        self.user = user
        self.alwaysUpToDate = alwaysUpToDate
        
        super.init(location: location, addressLocalizer: addressLocalizer)

        self.title = nameSupplier.name(user: user)
        self.subtitlePlaceholder = L10n.Map.Location.unknown
        self.accessibilityLabel = self.title
    }
    
    override public func update() {
        subtitle = addressLocalizer.short(annotation: self)
    }
}
