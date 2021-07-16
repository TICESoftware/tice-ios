//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import Pulley

extension PulleyPosition: Comparable {
    public static func < (lhs: PulleyPosition, rhs: PulleyPosition) -> Bool {
        if rhs == .closed {
            return false
        }
        if lhs == .closed {
            return true
        }
        return lhs.rawValue < rhs.rawValue
    }
}
