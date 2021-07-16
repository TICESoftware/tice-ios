//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import UserNotifications
import Swinject
import PromiseKit
import GRDB

class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    var container: Container!

    var storageManager: ApplicationStorageManagerType!
    var pushReceiver: PushReceiverType!
    var deepLinkParser: DeepLinkParserType!
    
    weak var notificationDelegate: NotificationDelegate?
    
    var initialized = false
    
    var handlers: [NotificationAction: Handler] = [:]

    func setup() -> Bool {
        container = DependencyRegistrator().extensionContainer()

        guard let storedAppVersion = container.resolve(VersionStorageManagerType.self)!.loadVersion() else {
            logger.error("Could not determine app version.")
            return false
        }

        let appVersion = Bundle.main.appVersion
        guard appVersion == storedAppVersion else {
            logger.warning("Abort execution in NSE because current version (\(appVersion)) is not equal stored version (\(storedAppVersion)).")
            return false
        }

        do {
            try container.resolve(DatabaseManagerType.self)!.setupDatabase()
            let database = container.resolve(DatabaseWriter.self)!
            try logger.attachStorage(database: database)
        } catch {
            logger.error("Failed to setup database: \(String(describing: error))")
            return false
        }

        let signedInUserController = container.resolve(SignedInUserManagerType.self)!
        signedInUserController.setup()

        guard signedInUserController.signedInUser != nil else {
            logger.error("Signed in user not available.")
            return false
        }

        container.register(NotificationManagerType.self) { _ in self }

        storageManager = container.resolve(ApplicationStorageManagerType.self)!
        pushReceiver = container.resolve(PushReceiverType.self)!
        deepLinkParser = container.resolve(DeepLinkParserType.self)!

        container.resolve(ConversationManagerType.self)!.registerHandler()
        container.resolve(GroupNotificationReceiverType.self)!.registerHandler()
        container.resolve(ChatMessageReceiverType.self)!.registerHandler()

        signedInUserController.teamBroadcaster = container.resolve(TeamBroadcaster.self)!

        container.resolve(PostOfficeType.self)!.decodingSuccessInterceptor = updateBestAttempt(payloadContainerBundle:)
        _ = container.resolve(MailboxType.self)!
        container.resolve(TooFewOneTimePrekeysHandlerType.self)!.registerHandler()

        initialized = true
        
        return true
    }

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
        
        bestAttemptContent?.title = L10n.Notification.Placeholder.title
        bestAttemptContent?.body = L10n.Notification.Placeholder.body

        if initialized {
            logger.debug("Continuing NSE instance: \(ObjectIdentifier(self))")
        } else {
            logger.debug("Setting up fresh NSE instance: \(ObjectIdentifier(self))")
            guard setup() else {
                logger.error("Setup error. Aborting.")
                fireBestAttempt()
                return
            }
        }

        if storageManager.applicationIsActive() {
            logger.debug("Extension was called to handle notification although app seems to be active. Not handling notification.")
            fireBestAttempt()
            return
        }

        logger.debug("Handling remote notification in extension.")

        self.pushReceiver.didReceiveRemoteNotification(userInfo: request.content.userInfo) { result in
            guard result == .newData else {
                logger.warning("Finish processing remote notification without result newData. Showing best attempt content.")
                self.fireBestAttempt()
                return
            }
        }
    }
    
    override func serviceExtensionTimeWillExpire() {
        logger.warning("We are running out of time processing remote notification in extension.")
        fireBestAttempt()
    }

    private func fireBestAttempt() {
        guard let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent else {
            logger.error("Not displaying remote notification because content is not set (anymore).")
            return
        }

        logger.debug("Fire best attempt in extension. Title: \(bestAttemptContent.title), body: \(bestAttemptContent.body)")

        contentHandler(bestAttemptContent)
        self.contentHandler = nil

        container.removeAll()
    }

    private func updateBestAttempt(payloadContainerBundle: PayloadContainerBundle) {
        switch payloadContainerBundle.payloadContainer.payloadType {
        case .groupUpdateV1:
            bestAttemptContent?.title = "Group update!"
            bestAttemptContent?.body = "A group has been updated."
        default:
            break
        }
    }
}

extension NotificationService: NotificationManagerType {

    func requestAuthorization(completionHandler: ((Bool) -> Void)?) {
    }
    
    func triggerNotification(title: String, body: String, state: AppState, category: NotificationCategory?, userInfo: [String: Any]) {
        bestAttemptContent?.title = title
        bestAttemptContent?.body = body
        
        if let categoryIdentifier = category?.rawValue {
            bestAttemptContent?.categoryIdentifier = categoryIdentifier
        }
        
        if let url = try? deepLinkParser.deepLink(state: state) {
            bestAttemptContent?.userInfo["url"] = url.absoluteString
        }
        
        bestAttemptContent?.userInfo.merge(userInfo, uniquingKeysWith: { _, new in new })

        fireBestAttempt()
    }
    
    func updateApplicationBadge(count: Int) {
        bestAttemptContent?.badge = NSNumber(value: count)
    }
    
    func removeAllPendingNotifications() {}
    
    func removePendingNotifications(with identifiers: [String]) {}
    
    func pendingNotifications() -> Promise<[UNNotificationRequest]> { return .value([]) }
}
