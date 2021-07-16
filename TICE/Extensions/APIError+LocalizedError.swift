//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels

extension APIError: LocalizedError {
    public var errorDescription: String? {
        return "\(type) - \(description)"
    }
}
