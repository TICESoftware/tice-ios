//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation

extension String {
    var data: Data { data(using: .utf8)! }
}

extension Data {
    var utf8String: String { String(data: self, encoding: .utf8)! }
}
