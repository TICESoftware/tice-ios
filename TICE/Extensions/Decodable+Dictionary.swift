//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation

extension Decodable {
    init(dictionary: [AnyHashable: Any], decoder: JSONDecoder) throws {
        let data = try JSONSerialization.data(withJSONObject: dictionary, options: .prettyPrinted)
        self = try decoder.decode(Self.self, from: data)
    }
}
