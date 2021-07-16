//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import Version

protocol VersionStorageManagerType {
    func store(version: Version)
    func loadVersion() -> Version?
}
