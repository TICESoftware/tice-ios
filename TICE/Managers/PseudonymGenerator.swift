//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation

protocol PseudonymGeneratorType {
    func pseudonym(userId: UserId) -> String
}

class PseudonymGenerator: PseudonymGeneratorType {

    private let names: [String]

    init(url: URL) {
        // swiftlint:disable:next force_try
        let allNames = try! String(contentsOf: url)
        names = allNames.split(separator: "\n").map(String.init)
    }

    func pseudonym(userId: UserId) -> String {
        let index = abs(userId.uuidString.hashCode) % names.count
        return names[index]
    }
}
