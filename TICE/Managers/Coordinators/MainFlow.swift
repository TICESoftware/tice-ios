//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import Swinject
import SwinjectStoryboard
import SwinjectAutoregistration
import UIKit
import PromiseKit
import UserNotifications

protocol MainFlow: Coordinator {

    func start()
    
    func didTapSettings()
    func failDeregisterUser(error: Error?)
    func failRenameUser(error: Error?)
    func didDeregister()

    func createTeam(source: String)
    func cancel(createTeamFlow: CreateTeamFlow, didDismiss: Bool)
    func finish(createTeamFlow: CreateTeamFlow, team: Team)

    func showTeamScreen(demoTeam: DemoTeam, animated: Bool)
    func finish(demoFlow: DemoFlow)
    
    func showTeamScreen(team: Team, animated: Bool)
    
    func showTeamSettingsScreen(for team: Team, animated: Bool)
    
    func changeTeamName(for team: Team)
    func cancel(changeNameFlow: ChangeNameFlow)
    func finish(changeNameFlow: ChangeNameFlow)

    func handleDeepLink(to state: AppState.MainState) -> Promise<Void>

    func failAddTeam(error: Error?)

    func didJoinTeam(team: Team)
    func failJoinTeam(error: Error?)

    func didLeaveOrDeleteTeam()
    func failLeaveOrDeleteTeam(error: Error?)

    func createMeetup(in team: Team, meetingPoint: LocationAnnotation?)
    func finish(createMeetupFlow: CreateMeetupFlow)
    func didFailCreateMeetup(error: Error?)

    func showShareScreen(for team: Team)
    func showMeetupSettingsScreen(for meetup: Meetup, animated: Bool)

    func didJoinMeetup()
    func failJoinMeetup(error: Error?)

    func didLeaveOrDeleteMeetup()
    func failLeaveOrDeleteMeetup(error: Error?)

    func showChat(for team: Team, animated: Bool)
    func leaveChat()
    
    func shouldShow(notification: UNNotification) -> Bool
}

enum MainCoordinatorError: Error {
    case unknownState
    case teamNotFound
    case meetupNotFound
    case publicGroupNotFound
    case invalidDeepLink
}

class MainCoordinator: NSObject, Coordinator {

    typealias State = AppState.MainState
    
    weak var parent: AppFlow?

    let window: UIWindow
    let storyboard: UIStoryboard
    let resolver: Swinject.Resolver
    
    let notifier: Notifier
    let tracker: TrackerType

    let navigationController = MainNavigationController()

    var teamManager: TeamManagerType { return resolver~> }
    var meetupManager: MeetupManagerType { return resolver~> }
    var groupStorageManager: GroupStorageManagerType { return resolver~> }
    var locationSharingManager: LocationSharingManagerType { return resolver~> }
    var demoManager: DemoManagerType { return resolver~> }
    var backend: TICEAPI { return resolver~> }
    
    private var teamObserverToken: ObserverToken?
    private var meetupObserverToken: ObserverToken?
    
    var children: [Coordinator] = []

    private var states: [State] = []
    private var backActions: [(Bool) -> Void] = []
    private var currentState: State { states.last ?? .unknown }
    private var inTransition: Bool = false

    init(parent: AppFlow, notifier: Notifier, tracker: TrackerType) {
        self.parent = parent
        self.window = parent.window
        self.storyboard = parent.storyboard
        self.resolver = parent.resolver
        self.notifier = notifier
        self.tracker = tracker

        super.init()
        
        if ProcessInfo.processInfo.arguments.contains("-FASTLANE_SNAPSHOT") {
            let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(navBarTapped(_:)))
            navigationController.navigationBar.addGestureRecognizer(tapRecognizer)
            
            let doubleTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(navBarDoubleTapped(_:)))
            doubleTapRecognizer.numberOfTapsRequired = 2
            navigationController.navigationBar.addGestureRecognizer(doubleTapRecognizer)
        }
        
        teamObserverToken = groupStorageManager.observeTeams(queue: .main) { [unowned self] teams in
            let teamIds = teams.map(\.groupId)
            switch self.currentState {
            case .team(team: let teamGroupId):
                if !teamIds.contains(teamGroupId) { self.didLeaveOrDeleteTeam() }
            case .teamSettings(team: let teamGroupId):
                if !teamIds.contains(teamGroupId) { self.didLeaveOrDeleteTeam() }
            case .createMeetup(team: let teamGroupId):
                if !teamIds.contains(teamGroupId) { self.didLeaveOrDeleteTeam() }
            case .meetupSettings(team: let teamGroupId, meetup: _):
                if !teamIds.contains(teamGroupId) { self.didLeaveOrDeleteTeam() }
            default:
                break
            }
        }
        
        meetupObserverToken = groupStorageManager.observeMeetups(queue: .main) { [unowned self] meetups in
            let meetupIds = meetups.map(\.groupId)
            if case .meetupSettings(team: _, meetup: let meetupGroupId) = self.currentState {
                if !meetupIds.contains(meetupGroupId) { DispatchQueue.main.async { self.didLeaveOrDeleteMeetup() } }
            }
        }
    }
    
    @objc
    func navBarTapped(_ gestureRecognizer: UIGestureRecognizer) {
        window.overrideUserInterfaceStyle = .light
    }

    @objc
    func navBarDoubleTapped(_ gestureRecognizer: UIGestureRecognizer) {
        window.overrideUserInterfaceStyle = .dark
    }
    
    deinit {
        teamObserverToken = nil
        meetupObserverToken = nil
    }
    
    private func show(viewController: UIViewController, newState: State, modal: Bool, animated: Bool = true) {
        if modal {
            navigationController.present(viewController, animated: animated, completion: nil)
            viewController.presentationController?.delegate = self
            backActions.append { [weak self] animated in
                self?.navigationController.dismiss(animated: animated, completion: nil)
                self?.popState()
            }
        } else {
            navigationController.pushViewController(viewController, animated: animated)
            backActions.append { [weak self] animated in
                self?.inTransition = true
                self?.navigationController.popViewController(animated: animated)
                self?.popState()
            }
        }
        proceed(to: newState)
    }
    
    private func dismiss(animated: Bool = true) {
        let action = backActions.last
        action?(animated)
    }

    private func proceed(to newState: State) {
        let previousState = currentState
        states.append(newState)

        tracker.log(action: .screen, category: .app, detail: currentState.trackingName)
        logger.debug("Coordinator - proceed from \(String(describing: previousState)) to \(String(describing: currentState))")
    }
    
    private func popState() {
        let previousState = currentState
        _ = backActions.removeLast()
        states.removeLast()
        tracker.log(action: .screen, category: .app, detail: currentState.trackingName)
        logger.debug("Coordinator - back from \(String(describing: previousState)) to \(String(describing: currentState))")
    }
    
    private func popToRoot() {
        self.navigationController.popToRootViewController(animated: false)
        self.navigationController.dismiss(animated: true, completion: nil)
        self.children = []
        states = [.groups]
        backActions = []
        logger.debug("Coordinator - popping all view controllers. Back to state \(currentState)")
    }
}

extension MainCoordinator: MainFlow {

    func start() {
        let teams: [Team]
        do {
            teams = try groupStorageManager.loadTeams()
        } catch {
            logger.error("Failed to load data for groups view model: \(String(describing: error))")
            return
        }

        let teamsViewController = storyboard.instantiateViewController(TeamsViewController.self)
        teamsViewController.viewModel = resolver.resolve(TeamsViewModel.self, arguments: self as MainFlow, teams)

        navigationController.delegate = self
        navigationController.setViewControllers([teamsViewController], animated: true)

        window.rootViewController = navigationController

        proceed(to: .groups)
    }

    func didTapSettings() {
        let settingsViewController = storyboard.instantiateViewController(SettingsViewController.self)
        settingsViewController.viewModel = resolver.resolve(SettingsViewModel.self, argument: self as MainFlow)
        show(viewController: settingsViewController, newState: .settings, modal: false, animated: true)
    }
    
    func showTeamScreen(demoTeam: DemoTeam, animated: Bool) {
        let demoFlow = resolver.resolve(DemoFlow.self, arguments: self as MainFlow, navigationController as UINavigationController)!
        let presented = demoFlow.start()
        children.append(demoFlow)
        show(viewController: presented, newState: .demo, modal: false)
    }

    func showTeamScreen(team: Team, animated: Bool) {
        do {
            let memberships = try groupStorageManager.loadMemberships(groupId: team.groupId)
            let users: [User] = try memberships.map { try groupStorageManager.user(for: $0) }
            
            let teamMapViewController = storyboard.instantiateViewController(TeamMapViewController.self)
            teamMapViewController.viewModel = resolver.resolve(TeamMapViewModel.self, arguments: self as MainFlow, team, users)
            teamMapViewController.chatViewModel = resolver.resolve(TeamMapChatViewModel.self, arguments: self as MainFlow, team)
            
            let teamViewController = storyboard.instantiateViewController(TeamViewController.self)
            teamViewController.viewModel = resolver.resolve(TeamViewModel.self, arguments: self as MainFlow, team)
            teamViewController.groupMapViewController = teamMapViewController
            show(viewController: teamViewController, newState: .team(team: team.groupId), modal: false, animated: animated)
        } catch {
            logger.error("Could not load data for team settings screen: \(String(describing: error))")
            show(error: error)
        }
    }
    
    func showTeamSettingsScreen(for team: Team, animated: Bool) {
        let signedInUser = resolver.resolve(SignedInUser.self)!
        let members: [Member]
        let admin: Bool
        do {
            members = try groupStorageManager.members(groupId: team.groupId)
            admin = try groupStorageManager.loadMembership(userId: signedInUser.userId, groupId: team.groupId).admin
        } catch {
            logger.error("Could not load data for team settings screen: \(String(describing: error))")
            show(error: error)
            return
        }

        let locationSharingStates = locationSharingManager.locationSharingStates(groupId: team.groupId)
        let teamSettingsViewController = storyboard.instantiateViewController(TeamSettingsViewController.self)
        teamSettingsViewController.viewModel = resolver.resolve(TeamSettingsViewModel.self, arguments: self as MainFlow, team, members, admin, locationSharingStates)

        show(viewController: teamSettingsViewController, newState: .teamSettings(team: team.groupId), modal: false, animated: animated)
    }

    func changeTeamName(for team: Team) {
        let changeNameFlow = resolver.resolve(ChangeNameFlow.self, arguments: self as MainFlow, team)!
        let presented = changeNameFlow.start()
        children.append(changeNameFlow)
        
        show(viewController: presented, newState: .changeName(team: team.groupId), modal: true)
    }

    func cancel(changeNameFlow: ChangeNameFlow) {
        remove(child: changeNameFlow)
        dismiss()
    }

    func finish(changeNameFlow: ChangeNameFlow) {
        remove(child: changeNameFlow)
        dismiss()
    }
    
    func handleDeepLink(to state: State) -> Promise<Void> {
        guard currentState != state else {
            logger.info("Already in state \(state). Aborting.")
            return .value
        }
        
        let action: () -> Void
        switch state {
        case .team(team: let teamId):
            guard let team = teamManager.teamWith(groupId: teamId) else {
                return .init(error: MainCoordinatorError.teamNotFound)
            }
            action = {
                self.popToRoot()
                self.showTeamScreen(team: team, animated: true)
            }
        case .chat(team: let teamId):
            guard let team = teamManager.teamWith(groupId: teamId) else {
                return .init(error: MainCoordinatorError.teamNotFound)
            }
            action = {
                self.popToRoot()
                self.showTeamScreen(team: team, animated: false)
                self.showChat(for: team, animated: true)
            }
        case .meetupSettings(team: let teamId, meetup: let meetupId):
            guard let team = teamManager.teamWith(groupId: teamId) else {
                return .init(error: MainCoordinatorError.teamNotFound)
            }
            let meetup: Meetup
            do {
                guard let meetupInTeam = try groupStorageManager.loadMeetup(meetupId) else {
                    return .init(error: MainCoordinatorError.meetupNotFound)
                }
                meetup = meetupInTeam
            } catch {
                return .init(error: MainCoordinatorError.meetupNotFound)
            }
            
            action = {
                self.popToRoot()
                self.showTeamScreen(team: team, animated: false)
                self.showMeetupSettingsScreen(for: meetup, animated: true)
            }
        case .join(team: let team):
            action = {
                self.popToRoot()
                self.showJoinTeam(for: team)
            }
        default:
            logger.warning("Don't know how to switch to state \(state). Aborting.")
            return .init(error: MainCoordinatorError.unknownState)
        }
        
        switch currentState {
        case .changeName, .createTeam, .createMeetupInNewGroup, .createMeetup:
            return firstly {
                askForUserConfirmation(title: L10n.Deeplink.Confirmation.title, message: L10n.Deeplink.Confirmation.body, action: L10n.Deeplink.Confirmation.openLink)
            }.done(on: .main) {
                action()
            }
        case .groups, .settings, .team, .teamSettings, .meetupSettings, .join, .chat, .demo:
            let (promise, seal) = Promise<Void>.pending()
            DispatchQueue.main.async {
                action()
                seal.fulfill_()
            }
            return promise
        case .unknown:
            logger.warning("Tried to deeplink to group screen but am in unknown state. Not doing anything…")
            return .init(error: MainCoordinatorError.unknownState)
        }
    }

    func showJoinTeam(for team: Team) {
        let joinTeamViewController = storyboard.instantiateViewController(JoinTeamViewController.self)
        joinTeamViewController.viewModel = resolver.resolve(JoinTeamViewModel.self, arguments: self as MainFlow, team)
        joinTeamViewController.viewModel.delegate = joinTeamViewController
        show(viewController: joinTeamViewController, newState: .join(team: team), modal: false, animated: true)
    }

    func failAddTeam(error: Error?) {
        show(error: error)
    }

    func didJoinTeam(team: Team) {
        let signedInUser = resolver.resolve(SignedInUser.self)!
        let meetupState: MeetupState
        do {
            meetupState = try groupStorageManager.meetupState(teamId: team.groupId, userId: signedInUser.userId)
        } catch {
            logger.error("Could not determine meetup state: \(String(describing: error))")
            return
        }
        
        if case .invited(let meetup) = meetupState {
            firstly { () -> Promise<Void> in
                self.dismiss(animated: false)
                self.showTeamScreen(team: team, animated: true)
                return askForUserConfirmation(title: L10n.JoinGroup.ConfirmJoinMeetup.title, message: L10n.JoinGroup.ConfirmJoinMeetup.body, action: L10n.JoinGroup.ConfirmJoinMeetup.join)
            }.then {
                self.meetupManager.join(meetup)
            }.catch { error in
                self.show(error: error)
            }
        } else {
            dismiss()
        }
    }

    func failJoinTeam(error: Error?) {
        show(error: error)
    }

    func didLeaveOrDeleteTeam() {
        popToRoot()
    }

    func failLeaveOrDeleteTeam(error: Error?) {
        show(error: error)
    }

    func createTeam(source: String) {
        let createTeamFlow = resolver.resolve(CreateTeamFlow.self, arguments: self as MainFlow, source)!
        let presented = createTeamFlow.start()
        children.append(createTeamFlow)
        show(viewController: presented, newState: .createTeam, modal: true)
    }

    func cancel(createTeamFlow: CreateTeamFlow, didDismiss: Bool) {
        remove(child: createTeamFlow)

        if !didDismiss {
            dismiss()
        }
    }

    func finish(createTeamFlow: CreateTeamFlow, team: Team) {
        remove(child: createTeamFlow)
        dismiss(animated: false)
        showTeamScreen(team: team, animated: true)
    }

    func didDeregister() {
        guard let parent = parent else {
            logger.debug("No parent for flow \(self)")
            return
        }
        parent.startApplication()
    }

    func failDeregisterUser(error: Error?) {
        show(error: error)
    }

    func failRenameUser(error: Error?) {
        show(error: error)
    }

    func createMeetup(in group: Team, meetingPoint: LocationAnnotation?) {
        let createMeetupFlow = resolver.resolve(CreateMeetupFlow.self, argument: self as MainFlow)!
        createMeetupFlow.start(from: group, meetingPoint: meetingPoint)
        children.append(createMeetupFlow)
        backActions.append { _ in }
        proceed(to: .createMeetup(team: group.groupId))
    }

    func finish(createMeetupFlow: CreateMeetupFlow) {
        remove(child: createMeetupFlow)
        popState()
    }
    
    func finish(demoFlow: DemoFlow) {
        remove(child: demoFlow)
        navigationController.delegate = self
    }

    func didFailCreateMeetup(error: Error?) {
        show(error: error)
    }

    func showShareScreen(for team: Team) {
        (UIApplication.shared.delegate as? AppDelegate)?.resetDesign()
        let teamShareInvitation = resolver.resolve(TeamShareInvitation.self, argument: team)!
        let activityViewController = UIActivityViewController(activityItems: [teamShareInvitation], applicationActivities: nil)
        activityViewController.completionWithItemsHandler = { activityType, completed, _, _ in
            if activityType != nil && completed || activityType == nil && !completed {
                (UIApplication.shared.delegate as? AppDelegate)?.setupDesign()
            }
        }
        navigationController.present(activityViewController, animated: true, completion: nil)
    }

    func showMeetupSettingsScreen(for meetup: Meetup, animated: Bool) {
        let signedInUser = resolver.resolve(SignedInUser.self)!

        do {
            guard let team = try groupStorageManager.loadTeam(meetup.teamId) else { return }
            let members: [Member] = try groupStorageManager.members(groupId: meetup.groupId)
            let participating = try groupStorageManager.isMember(userId: signedInUser.userId, groupId: meetup.groupId)
            let teamMembers = try groupStorageManager.members(groupId: meetup.teamId)
            let nonMembers: [Member] = teamMembers.filter { member in !members.contains(where: { $0.user == member.user }) }
            
            let admin: Bool
            if try groupStorageManager.isMember(userId: signedInUser.userId, groupId: meetup.groupId) {
                admin = try groupStorageManager.loadMembership(userId: signedInUser.userId, groupId: meetup.groupId).admin
            } else {
                admin = false
            }
            
            let meetupSettingsViewController = storyboard.instantiateViewController(MeetupSettingsViewController.self)
            meetupSettingsViewController.viewModel = resolver.resolve(MeetupSettingsViewModel.self, arguments: self as MainFlow, team, meetup, participating, members, nonMembers, admin)
            meetupSettingsViewController.viewModel.delegate = meetupSettingsViewController
            show(viewController: meetupSettingsViewController, newState: .meetupSettings(team: meetup.teamId, meetup: meetup.groupId), modal: false, animated: animated)
        } catch {
            logger.error("Failed to load data for meetup settings screen: \(String(describing: error))")
            return
        }
    }

    func didJoinMeetup() {
        dismiss()
    }

    func failJoinMeetup(error: Error?) {
        show(error: error)
    }

    func didLeaveOrDeleteMeetup() {
        dismiss()
    }

    func failLeaveOrDeleteMeetup(error: Error?) {
        show(error: error)
    }

    func showChat(for team: Team, animated: Bool) {
        let chatViewModel = resolver.resolve(ChatViewModel.self, arguments: self as MainFlow, team)

        let chatViewController = storyboard.instantiateViewController(ChatViewController.self)
        chatViewController.viewModel = chatViewModel
        show(viewController: UINavigationController(rootViewController: chatViewController), newState: .chat(team: team.groupId), modal: true, animated: animated)
    }
    
    func leaveChat() {
        dismiss()
    }
    
    func shouldShow(notification: UNNotification) -> Bool {
        guard let notificationTeamId = notification.request.content.userInfo["teamId"] as? String else {
            return true
        }
        
        switch currentState {
        case .team(team: let teamId), .chat(team: let teamId), .teamSettings(team: let teamId):
            return teamId != UUID(uuidString: notificationTeamId)
        case .groups:
            return false
        default:
            return true
        }
    }
}

extension MainCoordinator: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        popState()
    }
}

extension MainCoordinator: UINavigationControllerDelegate {
    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        let wasInTransition = inTransition
        inTransition = false

        guard navigationController.transitionCoordinator?.presentationStyle != .pageSheet,
            let fromViewController = navigationController.transitionCoordinator?.viewController(forKey: .from),
            fromViewController != self.navigationController,
            !navigationController.viewControllers.contains(fromViewController),
            !wasInTransition else {
            return
        }
        popState()
    }
}
