//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UserNotifications
import PromiseKit

protocol NotificationDelegate: AnyObject {
    func shouldShow(notification: UNNotification) -> Bool
    func didOpen(notification: UNNotification)
    func handleDeepLink(to state: AppState) -> Promise<Void>
}

protocol NotificationManagerType: AnyObject {
    var notificationDelegate: NotificationDelegate? { get set }
    
    func setup()
    func requestAuthorization(completionHandler: ((Bool) -> Void)?)
    func triggerNotification(title: String, body: String, state: AppState, category: NotificationCategory?, userInfo: [String: Any])
    func updateApplicationBadge(count: Int)
    func removePendingNotifications(with identifiers: [String])
    func pendingNotifications() -> Promise<[UNNotificationRequest]>
    func removeAllPendingNotifications()
    
    typealias Handler = (UNNotificationResponse) -> Promise<AppState?>
    var handlers: [NotificationAction: Handler] { get set }
}

extension NotificationManagerType {
    func setup() { }
}
