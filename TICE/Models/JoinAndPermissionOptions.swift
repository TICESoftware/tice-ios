//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels

enum JoinModeUIOption: CustomStringConvertible {
    case open
    case closed

    init(_ joinMode: JoinMode) {
        switch joinMode {
        case .open:
            self = .open
        case .closed:
            self = .closed
        }
    }

    var description: String {
        switch self {
        case .open:
            return L10n.JoinMode.open
        case .closed:
            return L10n.JoinMode.closed
        }
    }

    var joinMode: JoinMode {
        switch self {
        case .open: return .open
        case .closed: return .closed
        }
    }
}

enum PermissionModeUIOption: CustomStringConvertible {
    case everyone
    case admin

    init(_ permissionMode: PermissionMode) {
        switch permissionMode {
        case .everyone:
            self = .everyone
        case .admin:
            self = .admin
        }
    }

    var description: String {
        switch self {
        case .everyone:
            return L10n.PermissionMode.everyone
        case .admin:
            return L10n.PermissionMode.admin
        }
    }

    var permissionMode: PermissionMode {
        switch self {
        case .everyone: return .everyone
        case .admin: return .admin
        }
    }
}
