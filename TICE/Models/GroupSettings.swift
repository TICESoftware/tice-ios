//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation

struct GroupSettings: Hashable, Codable {
    var owner: UserId
    var name: String?
}
