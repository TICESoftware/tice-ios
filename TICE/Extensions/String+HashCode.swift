//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation

extension String {
    var hashCode: Int {
        var h: Int32 = 0
        let asciiArray = unicodeScalars.filter { $0.isASCII }.map { $0.value }
        for i in asciiArray {
            h = 31 &* h &+ Int32(i)
        }
        return Int(h)
    }
}
