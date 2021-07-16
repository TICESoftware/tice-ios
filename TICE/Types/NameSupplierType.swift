//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation

protocol NameSupplierType {
    func name(user: User) -> String
    func name(team: Team) -> String
    func groupNameByOwner(owner userId: UserId) -> String
}
