//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import GRDB

struct LocationSharingState: Codable, Equatable, Hashable {
    let userId: UserId
    let groupId: GroupId
    var enabled: Bool
    var lastUpdated: Date

    init(userId: UserId, groupId: GroupId, enabled: Bool, lastUpdated: Date) {
        self.userId = userId
        self.groupId = groupId
        self.enabled = enabled
        self.lastUpdated = lastUpdated
    }
}

extension LocationSharingState: FetchableRecord, PersistableRecord {
    enum Columns {
        static let userId = Column(CodingKeys.userId)
        static let groupId = Column(CodingKeys.groupId)
        static let enabled = Column(CodingKeys.enabled)
        static let lastUpdated = Column(CodingKeys.lastUpdated)
    }
}
