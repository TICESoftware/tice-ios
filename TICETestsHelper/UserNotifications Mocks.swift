//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UserNotifications

// MARK: UNNotification

class MockUNNotification: UNNotification {
    convenience init(date: Date, request: UNNotificationRequest) {
        self.init(coder: UNNotificationMockCoder(date: date, request: request))!
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}

// MARK: UNNotificationResponse

class MockUNNotificationResponse: UNNotificationResponse {
    convenience init(notification: UNNotification, actionIdentifier: String) {
        self.init(coder: UNNotificationResponseMockCoder(notification: notification, actionIdentifier: actionIdentifier))!
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}

// MARK: UNNotificationSettings

class MockUNNotificationSettings: UNNotificationSettings {
    convenience init(authorizationStatus: UNAuthorizationStatus, alertSetting: UNNotificationSetting, badgeSetting: UNNotificationSetting, soundSetting: UNNotificationSetting) {
        self.init(coder: UNNotificationSettingsMockCoder(authorizationStatus: authorizationStatus, alertSetting: alertSetting, badgeSetting: badgeSetting, soundSetting: soundSetting))!
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}

class UNNotificationSettingsMockCoder: NSCoder {
    let authorizationStatus: UNAuthorizationStatus
    let alertSetting: UNNotificationSetting
    let badgeSetting: UNNotificationSetting
    let soundSetting: UNNotificationSetting

    init(authorizationStatus: UNAuthorizationStatus, alertSetting: UNNotificationSetting, badgeSetting: UNNotificationSetting, soundSetting: UNNotificationSetting) {
        self.authorizationStatus = authorizationStatus
        self.alertSetting = alertSetting
        self.badgeSetting = badgeSetting
        self.soundSetting = soundSetting
    }

    override var allowsKeyedCoding: Bool { true }

    override func decodeInt64(forKey key: String) -> Int64 {
        switch key {
        case "authorizationStatus": return Int64(authorizationStatus.rawValue)
        case "alertSetting": return Int64(alertSetting.rawValue)
        case "badgeSetting": return Int64(alertSetting.rawValue)
        case "soundSetting": return Int64(soundSetting.rawValue)
        default: return 0
        }
    }

    override func decodeBool(forKey key: String) -> Bool {
        return false
    }
}

class UNNotificationMockCoder: NSCoder {
    let date: Date
    let request: UNNotificationRequest

    init(date: Date, request: UNNotificationRequest) {
        self.date = date
        self.request = request
    }

    override var allowsKeyedCoding: Bool { true }

    override func decodeObject(forKey key: String) -> Any? {
        switch key {
        case "date": return date
        case "request": return request
        default: return nil
        }
    }
}

class UNNotificationResponseMockCoder: NSCoder {
    let notification: UNNotification
    let actionIdentifier: String

    init(notification: UNNotification, actionIdentifier: String) {
        self.notification = notification
        self.actionIdentifier = actionIdentifier
    }

    override var allowsKeyedCoding: Bool { true }

    override func decodeObject(forKey key: String) -> Any? {
        switch key {
        case "notification": return notification
        case "actionIdentifier": return actionIdentifier
        default: return nil
        }
    }
}
