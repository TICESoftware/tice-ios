//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels

protocol Group {
    var groupId: GroupId { get }
    var groupKey: SecretKey { get }
    var owner: UserId { get }
    var joinMode: JoinMode { get }
    var permissionMode: PermissionMode { get }
    var tag: GroupTag { get set }
}
