//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation

extension Bundle {
    var buildNumber: Int {
        // swiftlint:disable:next force_cast
        let stringVersion = object(forInfoDictionaryKey: kCFBundleVersionKey as String) as! String
        return Int(stringVersion)!
    }
}
