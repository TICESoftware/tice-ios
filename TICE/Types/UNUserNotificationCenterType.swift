//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UserNotifications

protocol UNUserNotificationCenterType: AnyObject {
    var delegate: UNUserNotificationCenterDelegate? { get set }

    func requestAuthorization(options: UNAuthorizationOptions, completionHandler: @escaping (Bool, Error?) -> Void)
    func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: ((Error?) -> Void)?)
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
    func getNotificationSettings(completionHandler: @escaping (UNNotificationSettings) -> Void)
    func getPendingNotificationRequests(completionHandler: @escaping ([UNNotificationRequest]) -> Void)
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeAllPendingNotificationRequests()
}

extension UNUserNotificationCenter: UNUserNotificationCenterType { }
