//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import PromiseKit
import Swinject
import SwinjectAutoregistration
import MessageUI
import GRDB
import BackgroundTasks

class AppCoordinator: NSObject, Coordinator {

    let window: UIWindow
    let storyboard: UIStoryboard
    let resolver: Swinject.Resolver
    let container: Swinject.Container
    
    var notificationManager: NotificationManagerType { return resolver.resolve(NotificationManagerType.self)! }
    var deepLinkParser: DeepLinkParserType { return resolver.resolve(DeepLinkParserType.self)! }
    
    var children: [Coordinator] = []
    var deepLink: URL?
    
    let logHistoryOffsetUserFeedback: TimeInterval
    let logHistoryOffsetMigrationFailure: TimeInterval
    
    var launchFlowFinished: Bool = false
    
    var backgroundTask: TaskType?
    let backgroundTaskRefreshIdentifier = "app.tice.TICE.backgroundTask.refresh"

    init(window: UIWindow, storyboard: UIStoryboard, resolver: Swinject.Resolver, container: Swinject.Container, logHistoryOffsetUserFeedback: TimeInterval, logHistoryOffsetMigrationFailure: TimeInterval) {
        self.window = window
        self.storyboard = storyboard
        self.resolver = resolver
        self.container = container
        self.logHistoryOffsetUserFeedback = logHistoryOffsetUserFeedback
        self.logHistoryOffsetMigrationFailure = logHistoryOffsetMigrationFailure
    }
}

extension AppCoordinator: AppFlow {

    func startApplication() {
        let migrationManager = resolver.resolve(MigrationManagerType.self)!
        guard let migrationPromise = migrationManager.migrate() else {
            finishMigration()
            return
        }

        window.rootViewController = storyboard.instantiateViewController(withIdentifier: "MigrationViewController")
        firstly {
            migrationPromise
        }.done {
            self.finishMigration()
        }.catch(on: .main) { error in
            logger.error("Migration error: \(String(describing: error))")
            if case MigrationManagerError.deprecatedVersion = error {
                self.handleMigrationFailure(error: .deprecatedAppVersion, allowRetry: false, allowFeedback: false)
            } else {
                self.handleMigrationFailure(error: .migrationFailed, allowRetry: true, allowFeedback: true)
            }
        }
    }

    func handleMigrationFailure(error: AppFlowError, allowRetry: Bool, allowFeedback: Bool) {
        let title = L10n.Alert.Error.title
        let message: String = error.localizedDescription
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        if allowRetry {
            let retryAction = UIAlertAction(title: L10n.AppFlow.MigrationError.retryActionTitle, style: .default) { _ in
                self.startApplication()
            }
            alertController.addAction(retryAction)
        }

        if allowFeedback && MFMailComposeViewController.canSendMail() {
            let feedbackAction = UIAlertAction(title: L10n.AppFlow.MigrationError.feedbackActionTitle, style: .default) { _ in
                let composeMailViewController = MFMailComposeViewController()
                composeMailViewController.mailComposeDelegate = self

                composeMailViewController.setToRecipients(["feedback@ticeapp.com"])
                composeMailViewController.setSubject("TICE: Feedback (Migration)")

                let fileName = "logs_\(Bundle.main.verboseVersionString).zip"
                do {
                    let logData = try logger.generateCompressedLogData(logLevel: .debug, since: Date().addingTimeInterval(self.logHistoryOffsetMigrationFailure))
                    composeMailViewController.addAttachmentData(logData, mimeType: "application/zip", fileName: fileName)
                } catch {
                    logger.error("Failed to generate log attachment: \(String(describing: error))")
                }

                self.window.topMostViewController?.present(composeMailViewController, animated: true, completion: nil)
            }
            alertController.addAction(feedbackAction)
        }

        window.topMostViewController?.present(alertController, animated: true, completion: nil)
    }

    func finishMigration() {
        logger.debug("Setting up database.")
        do {
            try resolver.resolve(DatabaseManagerType.self)!.setupDatabase()
            let database = resolver.resolve(DatabaseWriter.self)!
            try logger.attachStorage(database: database)
        } catch {
            logger.error("Error during database setup: \(String(describing: error))")
        }

        let storageManager = resolver.resolve(InstallationDateStorageManagerType.self)!
        if storageManager.loadInstallationDate() == nil {
            storageManager.store(installationDate: Date())
        }

        let loadingViewController = storyboard.instantiateViewController(LoadingViewController.self)
        loadingViewController.viewModel = resolver.resolve(ForceUpdateViewModel.self, argument: self as AppFlow)
        window.rootViewController = loadingViewController
    }

    func finishUpdateChecking() {
        let signedInUserStorage = resolver.resolve(SignedInUserStorageManagerType.self)!
        guard let signedInUser = signedInUserStorage.loadSignedInUser() else {
            finishHousekeeping()
            return
        }
        
        let loadingViewController = storyboard.instantiateViewController(LoadingViewController.self)
        loadingViewController.viewModel = resolver.resolve(MembershipCertificateRenewalViewModel.self, arguments: self as AppFlow, signedInUser)
        window.rootViewController = loadingViewController
    }
    
    func finishHousekeeping() {
        let deviceTokenManager = resolver.resolve(DeviceTokenManagerType.self)!
        deviceTokenManager.registerHandler()
        deviceTokenManager.registerDevice(remoteNotificationsRegistry: UIApplication.shared, forceRefresh: true).catch {
            logger.error("Requesting verification code in finishUpdateChecking failed: \(String(describing: $0))")
        }

        let signedInUserController = resolver.resolve(SignedInUserManagerType.self)!
        signedInUserController.setup()
        
        let tracker = resolver.resolve(TrackerType.self)!
        #if !DEVELOPMENT
        tracker.start()
        #endif
        tracker.logSessionStart()
        
        handleScheduledBackgroundTask()
        
        launchFlowFinished = true

        if signedInUserController.signedIn {
            let signedInUserManager = resolver.resolve(SignedInUserManagerType.self)!
            signedInUserManager.teamBroadcaster = resolver.resolve(TeamBroadcaster.self)!

            let teamManager = resolver.resolve(TeamManagerType.self)!
            teamManager.reloadAllTeams().catch { logger.error("Failed to reload teams: \(String(describing: $0))") }
            
            self.resolver.resolve(WebSocketReceiver.self)!.connect()
            
            startMainFlow()
        } else {
            let registerFlow = resolver.resolve(RegisterFlow.self, argument: self as AppFlow)!
            registerFlow.start()
            children.append(registerFlow)
        }
    }

    func finish(registerFlow: RegisterFlow) {
        remove(child: registerFlow)
        startMainFlow()
    }

    func startMainFlow() {
        logger.debug("Starting main flow")
        notificationManager.notificationDelegate = self
        
        let mainFlow = resolver.resolve(MainFlow.self, argument: self as AppFlow)!
        mainFlow.start()
        resolver.resolve(ApplicationStorageManagerType.self)!.setStartFlowFinished(true)
        resolver.resolve(NotificationManagerType.self)!.requestAuthorization(completionHandler: nil)
        children.append(mainFlow)
        
        guard let deepLink = deepLink else {
            return
        }
        
        self.deepLink = nil
        
        firstly {
            deepLinkParser.state(url: deepLink)
        }.then(on: .main) { state in
            self.handleDeepLink(to: state)
        }.catch { error in
            logger.error("Error during processing deep link. Reason: \(error)")
        }
    }

    var mainFlow: MainFlow? {
        return children.first(where: { $0 is MainFlow }) as? MainFlow
    }
    
    func handleDeepLink(to state: AppState) -> Promise<Void> {
        logger.debug("Handle deep link to state \(state)")
        switch state {
        case .main(let mainState):
            guard let mainFlow = mainFlow else { return .init(error: AppFlowError.noMainFlow) }
            return mainFlow.handleDeepLink(to: mainState)
        default:
            logger.warning("Can not handle deep link to state \(state)")
            return .init(error: AppFlowError.invalidDeepLink)
        }
    }
    
    func registerBackgroundTaskHandling() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskRefreshIdentifier, using: nil, launchHandler: { [weak self] in
            self?.scheduleBackgroundTaskHandling(task: $0)
        })
        scheduleBackgroundRefresh()
    }
    
    func scheduleBackgroundTaskHandling(task: TaskType) {
        self.backgroundTask = task
        
        if launchFlowFinished {
            handleScheduledBackgroundTask()
        }
    }
    
    func handleScheduledBackgroundTask() {
        guard let backgroundTask = self.backgroundTask else { return }
        self.backgroundTask = nil
        
        switch backgroundTask.identifier {
        case backgroundTaskRefreshIdentifier:
            handleBackgroundRefresh(task: backgroundTask)
        default:
            logger.warning("Can not handle background task with identifier \(backgroundTask.identifier)")
            backgroundTask.setTaskCompleted(success: false)
        }
    }
    
    private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskRefreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60)
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            logger.error("Failed to schedule background refresh task: \(error)")
        }
    }
    
    private func handleBackgroundRefresh(task: TaskType) {
        logger.debug("Starting background refresh.")
        
        let tracker = resolver.resolve(TrackerType.self)!
        tracker.log(action: .backgroundFetch, category: .app)
        
        let startTimestamp = Date()
        task.expirationHandler = {
            let elapsedTime = Date().timeIntervalSince(startTimestamp)
            logger.error("Received background refresh timeout after \(elapsedTime) s.")
            tracker.log(action: .backgroundFetchTimeout, category: .app, detail: nil, number: elapsedTime)
            task.setTaskCompleted(success: false)
        }
        
        guard let storedAppVersion = container.resolve(VersionStorageManagerType.self)!.loadVersion() else {
            logger.error("Could not determine app version. Aborting.")
            tracker.log(action: .backgroundFetchCompleted, category: .app, detail: "noVersion")
            task.setTaskCompleted(success: false)
            return
        }

        let appVersion = Bundle.main.appVersion
        guard appVersion == storedAppVersion else {
            logger.warning("Current version (\(appVersion)) is not equal stored version (\(storedAppVersion)). Aborting.")
            tracker.log(action: .backgroundFetchCompleted, category: .app, detail: "differsFromCurrentVersion")
            task.setTaskCompleted(success: false)
            return
        }
        
        guard resolver.resolve(SignedInUserManagerType.self)!.signedIn else {
            logger.debug("Completing background refresh because the user is not signed in.")
            tracker.log(action: .backgroundFetchCompleted, category: .app, detail: "noSignedInUser")
            task.setTaskCompleted(success: true)
            return
        }
        
        scheduleBackgroundRefresh()
        
        firstly {
            resolver.resolve(PostOfficeType.self)!.fetchMessages()
        }.done {
            try self.resolver.resolve(CryptoStorageManager.self)?.cleanUpCache(entriesOlderThan: Date(timeIntervalSinceNow: -24 * 60 * 60))
        }.done {
            let elapsedTime = Date().timeIntervalSince(startTimestamp)
            logger.debug("Completed background refresh after \(elapsedTime) s.")
            tracker.log(action: .backgroundFetchCompleted, category: .app, detail: "success")
            task.setTaskCompleted(success: true)
        }.catch {
            logger.error("Error executing background task in background: \($0)")
            tracker.log(action: .backgroundFetchCompleted, category: .app, detail: "error - \($0)")
            task.setTaskCompleted(success: false)
        }
    }
}

extension AppCoordinator: NotificationDelegate {
    
    func shouldShow(notification: UNNotification) -> Bool {
        return mainFlow?.shouldShow(notification: notification) ?? false
    }
    
    func didOpen(notification: UNNotification) {
        guard let notificationURLString = notification.request.content.userInfo["url"] as? String,
            let url = URL(string: notificationURLString) else {
            return
        }
        
        firstly {
            deepLinkParser.state(url: url)
        }.then(on: .main) { state in
            self.handleDeepLink(to: state)
        }.catch { error in
            logger.error("Error during processing notification link. Reason: \(error)")
        }
    }
}

extension AppCoordinator: MFMailComposeViewControllerDelegate {
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true) {
            if result == .failed {
                logger.error("Could not send feedback mail.")
            }
            self.handleMigrationFailure(error: .migrationFailed, allowRetry: true, allowFeedback: true)
        }
    }
}

protocol TaskType: AnyObject {
    var identifier: String { get }
    var expirationHandler: (() -> Void)? { get set }
    func setTaskCompleted(success: Bool)
}

extension BGTask: TaskType {}
