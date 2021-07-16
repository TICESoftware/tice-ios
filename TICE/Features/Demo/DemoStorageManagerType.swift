//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation

protocol DemoStorageManagerType: DeletableStorageManagerType {
    func store(state: DemoManagerState) throws
    func load() throws -> DemoManagerState?
}
