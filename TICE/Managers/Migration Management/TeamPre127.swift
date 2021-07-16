//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels
import GRDB

struct TeamPre127: Codable, Group {
    
    let groupId: GroupId
    let groupKey: SecretKey
    let owner: UserId
    let joinMode: JoinMode
    let permissionMode: PermissionMode
    var tag: GroupTag
    
    let url: URL
    var name: String?
    var meetupId: GroupId?
    
    var shareURL: URL {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.path = url.relativePath
        components.fragment = groupKey.base64URLEncodedString()
        
        return components.url!
    }
}

extension TeamPre127: Equatable {}

extension TeamPre127: PersistableRecord, FetchableRecord, TableRecord {
    static var databaseTableName: String = "team"
    static let meetup = hasOne(Meetup.self)
    var meetup: QueryInterfaceRequest<Meetup> { request(for: TeamPre127.meetup) }
}
