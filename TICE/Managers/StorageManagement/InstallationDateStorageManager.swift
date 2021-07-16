//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation

protocol InstallationDateStorageManagerType {
    func store(installationDate: Date)
    func loadInstallationDate() -> Date?
}

class InstallationDateStorageManager: InstallationDateStorageManagerType {

    let userDefaults: UserDefaults

    enum StorageKey: String {
        case installationDate
    }

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    func store(installationDate: Date) {
        userDefaults.set(installationDate, forKey: StorageKey.installationDate.rawValue)
    }

    func loadInstallationDate() -> Date? {
        userDefaults.object(forKey: StorageKey.installationDate.rawValue) as? Date
    }
}
