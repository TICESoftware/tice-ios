//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import CoreLocation
import TICEAPIModels

struct MemberLocation: Hashable {
    let userId: UserId
    let lastLocation: Location?
}
