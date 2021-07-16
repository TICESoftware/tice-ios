//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation

protocol UserStorageManagerType: DeletableStorageManagerType {
    func store(_ user: User) throws
    func loadUser(userId: UserId) throws -> User?
    func loadUsers() throws -> [User]
}
