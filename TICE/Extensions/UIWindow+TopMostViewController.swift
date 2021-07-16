//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit

extension UIWindow {
    var topMostViewController: UIViewController? {
        return rootViewController?.topMostViewController
    }
}

extension UIViewController {
    var topMostViewController: UIViewController? {

        if let nav = self as? UINavigationController,
            let visibleViewController = nav.visibleViewController {
            return visibleViewController.topMostViewController
        }

        if let tab = self as? UITabBarController,
            let selected = tab.selectedViewController {
            return selected.topMostViewController
        }

        if let presented = presentedViewController {
            return presented.topMostViewController
        }

        return self
    }
}
