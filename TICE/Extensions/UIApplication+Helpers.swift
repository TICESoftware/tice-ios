//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit

extension UIApplication {
    static func openSettings() {
        guard let settingsUrl = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(settingsUrl) else {
            logger.error("Cannot open settings url")
            return
        }
        UIApplication.shared.open(settingsUrl, completionHandler: nil)
    }
}
