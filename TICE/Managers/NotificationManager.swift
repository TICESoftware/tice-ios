//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import UserNotifications
import PromiseKit

enum NotificationAction: String {
    case join
    case respond
}

enum NotificationCategory: String {
    case meetingCreated
    case messageReceived
}

class NotificationManager: NSObject, NotificationManagerType {
    
    let notificationCenter: UNUserNotificationCenterType
    let pushReceiver: PushReceiverType
    let tracker: TrackerType
    let deepLinkParser: DeepLinkParserType
    
    var handlers: [NotificationAction: Handler] = [:]
    
    weak var notificationDelegate: NotificationDelegate?

    enum NotificationType: String {
        case local
        case remote
    }

    init(notificationCenter: UNUserNotificationCenterType, pushReceiver: PushReceiverType, tracker: TrackerType, deepLinkParser: DeepLinkParserType) {
        self.notificationCenter = notificationCenter
        self.pushReceiver = pushReceiver
        self.tracker = tracker
        self.deepLinkParser = deepLinkParser

        super.init()
    }

    func setup() {
        notificationCenter.delegate = self
        
        #if !EXTENSION
        let acceptAction = UNNotificationAction(identifier: NotificationAction.join.rawValue,
                                                title: L10n.Notification.Join.title,
                                                options: UNNotificationActionOptions.foreground)
        
        let options: UNNotificationCategoryOptions = [.allowAnnouncement]
        
        let meetingStartedCategory = UNNotificationCategory(identifier: NotificationCategory.meetingCreated.rawValue,
                                                            actions: [acceptAction],
                                                            intentIdentifiers: [],
                                                            options: options)
        
        let respondAction = UNTextInputNotificationAction(identifier: NotificationAction.respond.rawValue,
                                                          title: L10n.Notification.Message.title,
                                                          options: [],
                                                          textInputButtonTitle: L10n.Notification.Message.send,
                                                          textInputPlaceholder: L10n.Notification.Message.placeholder)
        
        let messageReceivedCategory = UNNotificationCategory(identifier: NotificationCategory.messageReceived.rawValue,
                                                             actions: [respondAction],
                                                             intentIdentifiers: [],
                                                             options: options)
        
        notificationCenter.setNotificationCategories([meetingStartedCategory, messageReceivedCategory])
        #endif
    }

    func requestAuthorization(completionHandler: ((Bool) -> Void)? = nil) {
        logger.debug("Request to authorize notifications")
        notificationCenter.getNotificationSettings { settings in
            logger.debug("Got current notification settings: \(settings)")
            
            let authorizationDescription = self.authorizationDescription(settings: settings)
            self.tracker.log(action: .notificationAuthorization, category: .app, detail: authorizationDescription)
            
            let unsufficientPermissions =
                settings.badgeSetting != .enabled ||
                settings.alertSetting != .enabled ||
                settings.soundSetting != .enabled
            
            guard settings.authorizationStatus == .notDetermined || unsufficientPermissions else {
                logger.warning("Already have notification authorization. Skipping.")
                return
            }
            
            logger.debug("Requesting notification authorization")
            self.notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if let error = error {
                    logger.error("Error while asking for notification permission. \(String(describing: error))")
                }

                logger.info("Notification permissions \(granted ? "have" : "have not") been granted.")
                self.tracker.log(action: .requestNotificationAuthorization, category: .app, detail: granted ? "YES" : "NO")
                completionHandler?(granted)
            }
        }
    }

    func triggerNotification(title: String, body: String, state: AppState, category: NotificationCategory?, userInfo: [String: Any]) {
        notificationCenter.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized && settings.alertSetting == .enabled else {
                logger.debug("Aborting notification due to notification settings.")
                return
            }

            logger.debug("Triggering local notification with title \"\(title)\" and body \"\(body)\".")
            
            var userInfo = userInfo
            if let url = try? self.deepLinkParser.deepLink(state: state) {
                userInfo["url"] = url.absoluteString
            }
            userInfo["type"] = NotificationType.local.rawValue

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = UNNotificationSound.default
            content.userInfo = userInfo

            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)

            self.notificationCenter.add(request) { error in
                if let error = error {
                    logger.error(String(describing: error))
                }
            }
        }
    }
    
    func updateApplicationBadge(count: Int) {
        notificationCenter.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized && settings.badgeSetting == .enabled else {
                logger.debug("Aborting updating badge number due to notification settings.")
                self.requestAuthorization(completionHandler: { granted in
                    if granted { self.updateApplicationBadge(count: count) }
                })
                return
            }
            
            #if !EXTENSION
            DispatchQueue.main.async {
                UIApplication.shared.applicationIconBadgeNumber = count
            }
            #endif
        }
    }
    
    func pendingNotifications() -> Promise<[UNNotificationRequest]> {
        let (promise, seal) = Promise<[UNNotificationRequest]>.pending()
        notificationCenter.getPendingNotificationRequests(completionHandler: seal.fulfill)
        return promise
    }
    
    func removePendingNotifications(with identifiers: [String]) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
    
    func removeAllPendingNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
    }
    
    private func authorizationDescription(settings: UNNotificationSettings) -> String {
        switch settings.authorizationStatus {
        case .notDetermined: return "NOTDETERMINED"
        case .authorized: return "AUTHORIZED"
        case .denied: return "DENIED"
        case .provisional: return "PROVISIONAL"
        case .ephemeral: return "EPHEMERAL"
        @unknown default: return "UNKNOWN \(settings.authorizationStatus.rawValue)"
        }
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        var notificationType: NotificationType
        if let configuredTypeString = notification.request.content.userInfo["type"] as? String, let configuredType = NotificationType(rawValue: configuredTypeString) {
            notificationType = configuredType
        } else {
            notificationType = .remote
        }

        let presentationOptions: UNNotificationPresentationOptions
        switch notificationType {
        case .remote:
            logger.debug("Received remote notification while app is in foreground. Passing over to push receiver.")
            pushReceiver.didReceiveRemoteNotification(userInfo: notification.request.content.userInfo, fetchCompletionHandler: nil)
            presentationOptions = []
        case .local:
            logger.debug("Should present local notification while app is in foreground? Asking delegate.")
            if notificationDelegate?.shouldShow(notification: notification) ?? false {
                logger.debug("Delegate said yes.")
                presentationOptions = [.alert, .sound, .badge]
            } else {
                logger.debug("Delegate said no.")
                presentationOptions = []
            }
        }
        
        completionHandler(presentationOptions)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        
        guard response.actionIdentifier != UNNotificationDefaultActionIdentifier,
            let action = NotificationAction(rawValue: response.actionIdentifier),
            let handler = self.handlers[action] else {
                notificationDelegate?.didOpen(notification: response.notification)
                completionHandler()
                return
        }
        
        firstly { () -> Promise<AppState?> in
            handler(response)
        }.then { state -> Promise<Void> in
            guard let state = state, let delegate = self.notificationDelegate else { return .value }
            return delegate.handleDeepLink(to: state)
        }.catch {
            logger.error("Handling notification response \(response) failed with \($0)")
        }.finally {
            completionHandler()
        }
    }
}
