//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import Version

class VersionStorageManager: VersionStorageManagerType {

    let userDefaults: UserDefaults

    enum StorageKey: String {
        case semanticVersion
    }

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    func store(version: Version) {
        userDefaults.set(version.description, forKey: StorageKey.semanticVersion.rawValue)
    }

    func loadVersion() -> Version? {
        guard let storedVersion = userDefaults.string(forKey: StorageKey.semanticVersion.rawValue) else { return nil }
        return try? Version(storedVersion)
    }
}
