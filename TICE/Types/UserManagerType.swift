//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import PromiseKit

protocol UserManagerType {
    func registerHandler()
    func user(_ userId: UserId) -> User?
    func getUser(_ userId: UserId) -> Promise<User>
    func reloadUsers() -> Promise<Void>
}
