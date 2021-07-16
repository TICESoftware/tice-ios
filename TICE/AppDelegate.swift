//
//  Copyright © 2018 TICE Software UG (haftungsbeschränkt). All rights reserved.
//

import UIKit
import Sniffer
import Swinject
import SwinjectStoryboard
import PromiseKit
import Shouter
import MetricKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var coordinator: AppFlow!
    var window: UIWindow?

    var container: Container!
    var resolver: Swinject.Resolver!
    var tracker: TrackerType!

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.

        #if DEBUG
        let window = ShakeDetectingWindow(frame: UIScreen.main.bounds)
        #else
        let window = UIWindow(frame: UIScreen.main.bounds)
        #endif

        setupDesign()
        setup(window: window, application: application)

        window.makeKeyAndVisible()
        self.window = window
        
        if ProcessInfo.processInfo.arguments.contains("UITESTING") {
            UIView.setAnimationsEnabled(false)
        }

        MXMetricManager.shared.add(self)

        if launchOptions?[.remoteNotification] != nil {
            logger.debug("App was launched after receiving remote notification.")
        }
        
        coordinator.registerBackgroundTaskHandling()

        return true
    }
    
    func resetDesign() {
        UINavigationBar.appearance().isTranslucent = false
        UINavigationBar.appearance().backgroundColor = nil
        UINavigationBar.appearance().barTintColor = nil
        UINavigationBar.appearance().tintColor = nil
        UINavigationBar.appearance().titleTextAttributes = nil
        UINavigationBar.appearance().largeTitleTextAttributes = nil
        UINavigationBar.appearance().prefersLargeTitles = false
        
        let standardApperance = UINavigationBarAppearance()
        standardApperance.configureWithDefaultBackground()
        
        let scrollEdgeAppearance = UINavigationBarAppearance()
        scrollEdgeAppearance.configureWithTransparentBackground()
        
        UINavigationBar.appearance().standardAppearance = standardApperance
        UINavigationBar.appearance().scrollEdgeAppearance = scrollEdgeAppearance
    }

    func setupDesign() {
        UINavigationBar.appearance().isTranslucent = false
        UINavigationBar.appearance().backgroundColor = .highlightBackground
        UINavigationBar.appearance().barTintColor = .highlight
        UINavigationBar.appearance().tintColor = .white
        UINavigationBar.appearance().titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.white]
        UINavigationBar.appearance().largeTitleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.white]
        UINavigationBar.appearance().prefersLargeTitles = true
        
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .highlightBackground
        appearance.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.white]
        appearance.largeTitleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.white]
        
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }

    func setup(window: UIWindow, application: UIApplication) {

        if let container = container {
            container.resetObjectScope(.container)
            container.resetObjectScope(.graph)
            container.resetObjectScope(.transient)
            container.resetObjectScope(.weak)
            container.removeAll()
        }
        
        let dependencyRegistrator = DependencyRegistrator()
        container = dependencyRegistrator.appContainer(window: window)

        let resolver = container.synchronize()
        container.registerSingleton(Resolver.self, factory: { _ in resolver })
        self.resolver = resolver
        
        PromiseKit.conf.Q.map = .global()
        
        let urlSessionConfiguration = resolver.resolve(URLSessionConfiguration.self)!
        logger.attachNetworkSniffer(urlSessionConfiguration: urlSessionConfiguration)

        let applicationStorageManager = resolver.resolve(ApplicationStorageManagerType.self)!
        applicationStorageManager.setStartFlowFinished(false)

        if application.applicationState != .background {
            applicationStorageManager.setApplicationIsRunningInForeground(true)
        }

        coordinator = resolver.resolve(AppFlow.self)!
        coordinator.startApplication()
        
        tracker = resolver.resolve(TrackerType.self)!

        Shouter.default.register(DidShakeDeviceObserver.self, observer: self)
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
        logger.debug("Application will resign active.")
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
        logger.debug("Application did enter background.")
        
        if resolver.resolve(ApplicationStorageManagerType.self)!.startFlowFinished() {
            logger.debug("Disconnect web socket.")
            let webSocketReceiver = resolver.resolve(WebSocketReceiver.self)!
            webSocketReceiver.disconnect()
        }

        resolver.resolve(ApplicationStorageManagerType.self)?.setApplicationIsRunningInForeground(false)
        
        do {
            try logger.cleanUp()
        } catch {
            logger.error("Error cleaning up logs: \(String(describing: error))")
        }
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
        let userId = resolver.resolve(SignedInUserManagerType.self)!.signedInUser?.userId.uuidString
        logger.debug("Application will enter foreground. UserId: \(userId ?? "n/a")")
        
        resolver.resolve(ApplicationStorageManagerType.self)?.setApplicationIsRunningInForeground(true)
        
        let taskIdentifier = application.beginBackgroundTask(withName: "MessageBulkFetch") {
            logger.error("Background execution time expired for fetching messages.")
        }
        
        logger.debug("Fetch deferred messages.")
        
        firstly {
            resolver.resolve(PostOfficeType.self)!.fetchMessages()
        }.catch {
            logger.warning("Could not fetch messages: \(String(describing: $0))")
        }.finally {
            UIApplication.shared.endBackgroundTask(taskIdentifier)
        }
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
        logger.debug("Application did become active.")

        guard resolver.resolve(ApplicationStorageManagerType.self)!.startFlowFinished() else {
            logger.debug("Not connecting web socket because start flow hasn't finished yet.")
            return
        }

        let webSocketReceiver = resolver.resolve(WebSocketReceiver.self)!
        webSocketReceiver.connect()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
        logger.warning("Application will terminate.")

        resolver.resolve(ApplicationStorageManagerType.self)?.setApplicationIsRunningInForeground(false)

        let meetups = try? resolver.resolve(GroupStorageManagerType.self)?.loadMeetups()
        let meetupCount = (meetups?.count).map(Double.init)
        tracker.log(action: .terminateApp, category: .app, detail: nil, number: meetupCount)
        
        MXMetricManager.shared.remove(self)
    }
    
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
            let url = userActivity.webpageURL
            else {
                logger.debug("Continue user activity called without webpage URL.")
                return false
        }

        return handle(url: url)
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        let sendingAppId = options[.sourceApplication].map { String(describing: $0) }
        tracker.log(action: .customURLScheme, category: .app, detail: sendingAppId)

        return handle(url: url)
    }

    private func handle(url: URL) -> Bool {
        guard resolver.resolve(ApplicationStorageManagerType.self)!.startFlowFinished() else {
            logger.debug("Not continuing user activity because start flow hasn't finished yet. Storing for later.")
            coordinator.deepLink = url
            return false
        }

        logger.debug("Continue user activity with webpage URL called.")

        let signedInUserController = resolver.resolve(SignedInUserManagerType.self)!
        guard signedInUserController.signedIn else {
            logger.warning("User not signed in. Aborting user activity.")
            return false
        }

        let deepLinkParser = resolver.resolve(DeepLinkParserType.self)!
        firstly {
            deepLinkParser.state(url: url)
        }.then(on: .main) { state in
            self.coordinator.handleDeepLink(to: state)
        }.catch { error in
            logger.error("Error during processing invitation. \(error)")
        }
        
        return true
    }

    // MARK: Remote notifications

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        logger.debug("Did register for remote notifications with device token \(deviceToken.reduce("", { $0 + String(format: "%02X", $1) }))")

        guard let deviceTokenManager = resolver.resolve(DeviceTokenManagerType.self) else {
            logger.error("Cannot process device token. No manager available.")
            return
        }

        deviceTokenManager.processDeviceToken(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        #if targetEnvironment(simulator)
        logger.debug("Did fail to register for remote notifications because app is run in simulator. That's fine.")
        #else
        logger.error("Did fail to register for remote notifications with error \(String(describing: error))")
        #endif
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard let aps = userInfo["aps"] as? [String: Any],
            !aps.keys.contains("alert") else {
                logger.debug("Not handling notification with alert in AppDelegate.")
                completionHandler(.noData)
                return
        }

        logger.debug("Received silent remote notification.")
        let pushReceiver = resolver.resolve(PushReceiverType.self)!
        pushReceiver.didReceiveRemoteNotification(userInfo: userInfo, fetchCompletionHandler: completionHandler)
    }
}

extension AppDelegate: DidShakeDeviceObserver {
    func didShakeDevice(motion: UIEvent.EventSubtype, event: UIEvent?) {
        guard !(window?.topMostViewController is LogViewController) else {
            return
        }
        let logViewController = resolver.resolve(LogViewController.self)!
        let navigationController = UINavigationController(rootViewController: logViewController)
        window?.topMostViewController?.present(navigationController, animated: true, completion: nil)
    }
}

extension AppDelegate: MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXMetricPayload]) {
        logger.debug("Received metrics.")
    }
}
