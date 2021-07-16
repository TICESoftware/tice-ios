//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import SwinjectStoryboard

extension UIStoryboard {
    public func instantiateViewController<T>(_ serviceType: T.Type) -> T {
        // swiftlint:disable:next force_cast
        return instantiateViewController(withIdentifier: String(describing: T.self)) as! T
    }
}
