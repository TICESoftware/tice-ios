//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//

import Foundation
import UIKit

class RoundImageView: UIImageView {
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
    }
}
