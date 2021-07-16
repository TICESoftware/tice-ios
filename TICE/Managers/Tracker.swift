//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import PromiseKit
import Shouter
import Beekeeper

struct TrackerAction: Equatable {
    
    var raw: String
    
    fileprivate init(raw: String) {
        self.raw = raw
    }
    
    public static let sessionStart: Self = TrackerAction(raw: "SessionStart")
    public static var sessionEnd: Self = TrackerAction(raw: "SessionEnd")
    
    public static var terminateApp: Self = TrackerAction(raw: "TerminateApp")
    
    public static var backgroundFetch: Self = TrackerAction(raw: "BackgroundFetch")
    public static var backgroundFetchCompleted: Self = TrackerAction(raw: "BackgroundFetchCompleted")
    public static var backgroundFetchTimeout: Self = TrackerAction(raw: "BackgroundFetchTimeout")
    
    public static var certificateRenewal: Self = TrackerAction(raw: "CertificateRenewal")

    public static var customURLScheme: Self = TrackerAction(raw: "CustomURLScheme")
    
    public static var locationAuthorization: Self = TrackerAction(raw: "LocationAuthorization")
    public static var notificationAuthorization: Self = TrackerAction(raw: "NotificationAuthorization")
    public static var requestNotificationAuthorization: Self = TrackerAction(raw: "RequestNotificationAuthorization")
    
    public static var showMapSearch: Self = TrackerAction(raw: "ShowMapSearch")
    public static var toggleFittingMap: Self = TrackerAction(raw: "ToggleFittingMap")
    public static var searchMap: Self = TrackerAction(raw: "SearchMap")
    public static var toggleUserTracking: Self = TrackerAction(raw: "ToggleUserTracking")
    
    public static var screen: Self = TrackerAction(raw: "Screen")
    
    public static var localization: Self = TrackerAction(raw: "Localization")
    public static var register: Self = TrackerAction(raw: "Register")
    public static var didRegister: Self = TrackerAction(raw: "DidRegister")
    
    public static var signIn: Self = TrackerAction(raw: "SignIn")
    public static var signOut: Self = TrackerAction(raw: "SignOut")
    public static var changeName: Self = TrackerAction(raw: "ChangeName")
    public static var changeLocationTracking: Self = TrackerAction(raw: "ChangeLocationTracking")
    
    public static var showCreateTeam: Self = TrackerAction(raw: "ShowCreateTeam")
    public static var createTeam: Self = TrackerAction(raw: "CreateTeam")
    public static var createTeamAndShareLocation: Self = TrackerAction(raw: "CreateTeamAndShareLocation")
    
    public static var leaveTeam: Self = TrackerAction(raw: "LeaveTeam")
    public static var deleteTeam: Self = TrackerAction(raw: "DeleteTeam")

    public static var createMeetup: Self = TrackerAction(raw: "CreateMeetup")
    public static var joinMeetup: Self = TrackerAction(raw: "JoinMeetup")
    public static var leaveMeetup: Self = TrackerAction(raw: "LeaveMeetup")
    
    public static var deleteMeetup: Self = TrackerAction(raw: "DeleteMeetup")
    public static var deleteAccount: Self = TrackerAction(raw: "DeleteAccount")
    public static var invite: Self = TrackerAction(raw: "Invite")
    
    public static var removeMember: Self = TrackerAction(raw: "RemoveMember")
    public static var promoteMember: Self = TrackerAction(raw: "PromoteMember")

    public static var missedMeetupUpdate: Self = TrackerAction(raw: "MissedMeetupUpdate")
    
    public static var resetDemo: Self = TrackerAction(raw: "ResetDemo")
    public static var endDemo: Self = TrackerAction(raw: "EndDemo")
    
    public static var pause: Self = TrackerAction(raw: "Pause")
    public static var unpause: Self = TrackerAction(raw: "Unpause")
    
    public static var error: Self = TrackerAction(raw: "Error")
    public static var cancel: Self = TrackerAction(raw: "Cancel")
    
    public static func changeDemoState(step: DemoManagerStep, previousStep: DemoManagerStep) -> TrackerAction {
        return TrackerAction(raw: "\(previousStep.description) > \(step.description)")
    }
}

struct TrackerCategory: Equatable {
    
    var raw: String
    
    fileprivate init(raw: String) {
        self.raw = raw
    }
    
    public static var app: Self = .init(raw: "App")
    public static var createTeam: Self = .init(raw: "CreateTeam")
    public static var register: Self = .init(raw: "Register")
    public static var demo: Self = .init(raw: "Demo")
    public static var conversation: Self = .init(raw: "Conversation")
    public static var membershipRenewal: Self = .init(raw: "MembershipRenewal")
}

protocol TrackerType {

    func start()
    
    func logSessionStart()
    func logSessionEnd()
    
    func log(action: TrackerAction, category: TrackerCategory)
    func log(action: TrackerAction, category: TrackerCategory, detail: String?)
    func log(action: TrackerAction, category: TrackerCategory, detail: String?, number: Double?)
}

class Tracker: TrackerType {
    
    var beekeeper: BeekeeperType
    var installationDateStorageManager: InstallationDateStorageManagerType
    
    var sessionStart: Date?
    var notificationCenterTokens: [NSObjectProtocol] = []
    
    init(beekeeper: BeekeeperType, installationDateStorageManager: InstallationDateStorageManagerType) {
        self.beekeeper = beekeeper
        self.installationDateStorageManager = installationDateStorageManager
        
        notificationCenterTokens.append(NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil) { [unowned self] notification in self.applicationWillEnterForeground(notification: notification) })
        notificationCenterTokens.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [unowned self] notification in self.applicationDidEnterBackground(notification: notification) })
    }
    
    func start() {
        guard let installationDate = installationDateStorageManager.loadInstallationDate() else {
            logger.warning("Can not start tracking. Reason: Could not find installation date.")
            return
        }
        
        let buildNumber = Bundle.main.buildNumber
        beekeeper.setInstallDate(installationDate)
        beekeeper.setProperty(0, value: "iOS-\(buildNumber)")
        beekeeper.start()
    }
    
    func log(action: TrackerAction, category: TrackerCategory) {
        log(action: action, category: category, detail: nil)
    }
    
    func log(action: TrackerAction, category: TrackerCategory, detail: String?) {
        log(action: action, category: category, detail: detail, number: nil)
    }
    
    func log(action: TrackerAction, category: TrackerCategory, detail: String?, number: Double?) {
        logger.trace("TRACKING – name: \(action.raw), group: \(category.raw), detail: \(String(describing: detail)), value: \(String(describing: number))")
        beekeeper.track(name: action.raw, group: category.raw, detail: detail, value: number, custom: nil)
    }
    
    deinit {
        notificationCenterTokens.forEach {
            NotificationCenter.default.removeObserver($0)
        }
        notificationCenterTokens.removeAll()
    }
    
    func logSessionStart() {
        let language = Locale.preferredLanguages[0]
        log(action: .sessionStart, category: .app, detail: language)
        sessionStart = Date()
    }
    
    func logSessionEnd() {
        let sessionDuration = self.sessionStart.map { -$0.timeIntervalSinceNow }
        log(action: .sessionEnd, category: .app, detail: nil, number: sessionDuration)
    }
    
    func applicationWillEnterForeground(notification: Notification) {
        logSessionStart()
    }
    
    func applicationDidEnterBackground(notification: Notification) {
        logSessionEnd()
        sessionStart = nil
        
        guard let application = notification.object as? UIApplication else { return }
        
        let identifier = application.beginBackgroundTask(withName: "TrackingManagerDispatch") {
            logger.debug("TrackingManagerDispatch is going to expire")
        }
        
        beekeeper.dispatch {
            application.endBackgroundTask(identifier)
        }
    }
}
