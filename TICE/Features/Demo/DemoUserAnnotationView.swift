//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import MapKit

class DemoUserAnnotationView: MKAnnotationView {
    
    var viewModel: DemoUserAnnotationViewModel! {
        didSet {
            image = viewModel.image
            accessibilityIdentifier = viewModel.name
            displayPriority = .required
        }
    }
    
    override func prepareForDisplay() {
        super.prepareForDisplay()
        layer.borderWidth = 3
        layer.borderColor = UIColor.white.cgColor
        layer.cornerRadius = (image?.size.width ?? 0) / 2.0
        layer.masksToBounds = true
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        if selected {
            layer.setAffineTransform(CGAffineTransform.init(scaleX: 1.2, y: 1.2))
        } else {
            layer.setAffineTransform(CGAffineTransform.identity)
        }
    }
}

struct DemoUserAnnotationViewModel {
    var image: UIImage
    var name: String
}
