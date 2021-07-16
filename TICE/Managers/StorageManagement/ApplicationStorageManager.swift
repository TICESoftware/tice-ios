//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation

class ApplicationStorageManager: ApplicationStorageManagerType {

    let userDefaults: UserDefaults

    enum StorageKey: String {
        case appCanHandleNotifications
        case startFlowFinished
    }

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    func setApplicationIsRunningInForeground(_ value: Bool) {
        userDefaults.set(value, forKey: StorageKey.appCanHandleNotifications.rawValue)
    }

    func applicationIsActive() -> Bool {
        userDefaults.bool(forKey: StorageKey.appCanHandleNotifications.rawValue)
    }

    func setStartFlowFinished(_ value: Bool) {
        userDefaults.set(value, forKey: StorageKey.startFlowFinished.rawValue)
    }

    func startFlowFinished() -> Bool {
        userDefaults.bool(forKey: StorageKey.startFlowFinished.rawValue)
    }
}
