//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import MapKit

class UserAnnotationView: MKMarkerAnnotationView {
    
    var viewModel: UserAnnotationViewModel! {
        didSet {
            accessibilityIdentifier = viewModel.name
            glyphText = viewModel.initials
            markerTintColor = viewModel.color
            titleVisibility = .visible
            subtitleVisibility = .adaptive
            displayPriority = .required
            clusteringIdentifier = "user"
        }
    }
}

struct UserAnnotationViewModel {
    var name: String
    var initials: String
    var color: UIColor
}
