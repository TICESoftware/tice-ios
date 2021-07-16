//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import Swinject
import SwinjectStoryboard
import SwinjectAutoregistration
import CoreLocation

extension DependencyRegistrator {
    
    public func appContainer(window: UIWindow) -> Container {
        let container = Container { container in
            self.setupCommonContainer(container: container)
            self.setupAppContainer(container: container, window: window)
        }
        return container
    }
    
    private func setupAppContainer(container: Container, window: UIWindow) {
        setupCoordinators(container: container, config: config, window: window)
        setupViewControllers(container: container, config: config)
        setupViewModels(container: container, config: config)
        
        if ProcessInfo.processInfo.arguments.contains("SNAPSHOT") {
            setupSnapshot(container: container, config: config)
        }

        #if targetEnvironment(simulator)
        setupSimulatorMocks(container: container, config: config)
        #endif

        #if DEBUG
        if !ProcessInfo.processInfo.arguments.contains("SNAPSHOT") && !ProcessInfo.processInfo.arguments.contains("UITESTING") {
            setupDebug(container: container, config: config)
        }
        #endif
    }

    private func setupCoordinators(container: Container, config: Config, window: UIWindow) {
        container.register(AppFlow.self) { r in
            let storyboard = SwinjectStoryboard.create(name: "Main", bundle: Bundle.main, container: container)
            return AppCoordinator(
                window: window,
                storyboard: storyboard,
                resolver: r~>,
                container: container,
                logHistoryOffsetUserFeedback: config.logHistoryOffsetUserFeedback,
                logHistoryOffsetMigrationFailure: config.logHistoryOffsetMigrationFailure
            )
        }

        container.register(RegisterFlow.self) { _, coordinator in return RegisterCoordinator(parent: coordinator) }
        container.register(MainFlow.self) { r, coordinator in return MainCoordinator(parent: coordinator, notifier: r~>, tracker: r~>) }
        container.register(CreateTeamFlow.self) { r, coordinator, source in return CreateTeamCoordinator(tracker: r~>, parent: coordinator, source: source) }
        container.register(CreateMeetupFlow.self) { r, coordinator in return CreateMeetupCoordinator(meetupManager: r~>, signedInUser: r~>, parent: coordinator, tracker: r~>) }
        container.register(ChangeNameFlow.self) { _, coordinator, group in return ChangeNameCoordinator(parent: coordinator, team: group) }
        container.register(DemoFlow.self) { _, coordinator, navigationController in
            return DemoCoordinator(parent: coordinator, navigationController: navigationController)
        }
    }

    private func setupViewControllers(container: Container, config: Config) {
        container.storyboardInitCompleted(UINavigationController.self) { _, _ in }
        container.storyboardInitCompleted(LoadingViewController.self) { _, _ in }
        container.storyboardInitCompleted(MigrationViewController.self) { _, _ in }
        container.storyboardInitCompleted(RegisterViewController.self) { _, _ in }
        container.storyboardInitCompleted(TeamViewController.self) { _, _ in }
        container.storyboardInitCompleted(TeamMapViewController.self) { _, _ in }
        container.storyboardInitCompleted(MapViewController.self) { _, _ in }

        container.storyboardInitCompleted(TeamsViewController.self) { _, _ in }
        container.storyboardInitCompleted(TeamSettingsViewController.self) { _, _ in }
        container.storyboardInitCompleted(CreateTeamViewController.self) { _, _ in }
        container.storyboardInitCompleted(CreateMeetupViewController.self) { _, _ in }
        container.storyboardInitCompleted(MeetupSettingsViewController.self) { _, _ in }
        container.storyboardInitCompleted(SettingsViewController.self) { _, _ in }
        container.storyboardInitCompleted(AnnotationDetailViewController.self) { _, _ in }
        container.storyboardInitCompleted(ClusterAnnotationDetailViewController.self) { _, _ in }
        container.storyboardInitCompleted(JoinTeamViewController.self) { _, _ in }
        container.storyboardInitCompleted(ChangeTeamNameViewController.self) { r, c in
            c.nameSupplier = r~>
            c.groupNameLimit = config.groupNameLimit
            c.teamManager = r~>
        }
        container.storyboardInitCompleted(InviteViewController.self) { _, _ in }
        container.storyboardInitCompleted(EmptyDrawerViewController.self) { _, _ in }
        container.storyboardInitCompleted(ChatViewController.self) { _, _ in }
        container.storyboardInitCompleted(MapSearchViewController.self) { r, c in
            c.addressLocalizer = r~>
            c.tracker = r~>
        }
    }

    private func setupViewModels(container: Container, config: Config) {
        container.register(ForceUpdateViewModel.self) { r, coordinator in
            return ForceUpdateViewModel(updateChecker: r~>, coordinator: coordinator)
        }

        container.register(SettingsViewModel.self) { r, coordinator in
            return SettingsViewModel(coordinator: coordinator,
                                     backend: r~>,
                                     signedInUser: r~>,
                                     teamManager: r~>,
                                     groupManager: r~>,
                                     signedInUserManager: r~>,
                                     locationManager: r~>,
                                     nameSupplier: r~>,
                                     tracker: r~>,
                                     demoManager: r~>,
                                     logHistoryOffsetUserFeedback: config.logHistoryOffsetUserFeedback,
                                     signedInUserStorageManager: r~>,
                                     groupStorageManager: r~>,
                                     postOfficeStorageManager: r~>,
                                     conversationStorageManager: r~>,
                                     locationStorageManager: r~>,
									 userStorageManager: r~>,
                                     chatStorageManager: r~>,
                                     demoStorageManager: r~>,
                                     cryptoStorageManager: r ~> CryptoStorageManagerType.self)
        }

        container.register(TeamsViewModel.self) { r, coordinator, teams in
            return TeamsViewModel(coordinator: coordinator,
								   notifier: r~>,
								   teamManager: r~>,
								   groupManager: r~>,
								   groupStorageManager: r~>,
                                   locationSharingManager: r~>,
                                   chatManager: r~>,
                                   chatStorageManager: r~>,
								   signedInUser: r~>,
								   tracker: r~>,
                                   nameSupplier: r~>,
                                   demoManager: r~>,
								   resolver: r~>,
								   teams: teams)
        }
        container.register(RegisterViewModelType.self) { r, coordinator in
            return RegisterViewModel(coordinator: coordinator,
                                     cryptoManager: r~>,
                                     conversationCryptoMiddleware: r~>,
                                     deviceTokenManager: r~>,
                                     signedInUserController: r~>,
                                     backend: r~>,
                                     demoManager: r~>,
                                     notifier: r~>,
                                     tracker: r~>,
                                     resolver: r~>,
                                     showCancelTimeout: config.registerShowCancelTimeout,
                                     timeout: config.registerRoundTripTimeout,
                                     backendBaseURL: config.backendBaseURL)
        }
        container.register(UserAnnotation.self) { r, location, user, alwaysUpToDate in
            return UserAnnotation(location: location, user: user, alwaysUpToDate: alwaysUpToDate, nameSupplier: r~>, addressLocalizer: r~>)
        }
        container.register(LocationAnnotation.self) { r, location in
            return LocationAnnotation(location: location, addressLocalizer: r~>)
        }
        container.register(DemoUserAnnotation.self) { r, location, demoUser in
            return DemoUserAnnotation(location: location, demoUser: demoUser, demoManager: r~>, addressLocalizer: r~>)
        }
        container.autoregister(MapViewModel.self, initializer: MapViewModel.init)
        container.register(CreateTeamViewModel.self) { r, coordinator in
            return CreateTeamViewModel(coordinator: coordinator,
                                        teamManager: r~>,
                                        nameSupplier: r~>,
                                        signedInUser: r~>,
                                        tracker: r~>)
        }
        container.register(DemoTeamViewModel.self) { r, coordinator in
            return DemoTeamViewModel(demoManager: r~>, notifier: r~>, coordinator: coordinator)
        }
        container.register(DemoTeamMapViewModel.self) { r, coordinator in
            return DemoTeamMapViewModel(demoManager: r~>, signedInUser: r~>, notifier: r~>, resolver: r~>, coordinator: coordinator)
        }
        container.register(DemoTeamMapChatViewModel.self) { r, coordinator in
            return DemoTeamMapChatViewModel(demoManager: r~>, notifier: r~>, coordinator: coordinator)
        }
        container.register(DemoChatViewModel.self) { r, coordinator in
            return DemoChatViewModel(demoManager: r~>, notifier: r~>, coordinator: coordinator)
        }
        container.register(DemoTeamSettingsViewModel.self) { r, coordinator in
            return DemoTeamSettingsViewModel(demoManager: r~>, tracker: r~>, coordinator: coordinator)
        }
        container.register(TeamViewModel.self) { r, coordinator, team in
            return TeamViewModel(nameSupplier: r~>,
                                  groupStorageManager: r~>,
                                  userManager: r~>,
                                  avatarSupplier: r~>,
                                  notifier: r~>,
                                  coordinator: coordinator,
                                  team: team)
        }
        container.register(TeamMapViewModel.self) { r, coordinator, team, users in
            return TeamMapViewModel(coordinator: coordinator,
                                         signedInUser: r~>,
                                         groupManager: r~>,
                                         groupStorageManager: r~>,
                                         userManager: r~>,
                                         locationManager: r~>,
                                         locationSharingManager: r~>,
                                         nameSupplier: r~>,
                                         avatarSupplier: r~>,
                                         notificationRegistry: r~>,
                                         tracker: r~>,
                                         resolver: r~>,
                                         group: team,
                                         users: users)
        }
        container.register(TeamMapChatViewModel.self) { r, coordinator, team in
            return TeamMapChatViewModel(nameSupplier: r~>,
                                        chatStorageManager: r~>,
                                        userManager: r~>,
                                        avatarSupplier: r~>,
                                        notifier: r~>,
                                        coordinator: coordinator,
                                        team: team)
        }
        container.register(TeamSettingsViewModel.self) { r, coordinator, group, members, admin, locationSharingStates in
            return TeamSettingsViewModel(coordinator: coordinator,
                                                signedInUser: r~>,
                                                resolver: r~>,
                                                teamManager: r~>,
                                                locationSharingManager: r~>,
                                                groupStorageManager: r~>,
                                                nameSupplier: r~>,
                                                notifier: r~>,
                                                tracker: r~>,
                                                group: group,
                                                members: members,
                                                admin: admin,
                                                locationSharingStates: locationSharingStates)
        }
        container.register(CreateMeetupViewModel.self) { r, coordinator, group, meetingPoint in
            return CreateMeetupViewModel(coordinator: coordinator,
                                         meetupManager: r~>,
                                         teamManager: r~>,
                                         locationManager: r~>,
                                         addressLocalizer: r~>,
                                         team: group,
                                         meetingPoint: meetingPoint)
        }
        container.register(MeetupSettingsViewModel.self) { r, coordinator, team, meetup, participating, members, nonMembers, admin in
            return MeetupSettingsViewModel(coordinator: coordinator,
                                           meetupManager: r~>,
                                           teamManager: r~>,
                                           groupStorageManager: r~>,
                                           locationManager: r~>,
                                           signedInUser: r~>,
                                           nameSupplier: r~>,
                                           notifier: r~>,
                                           tracker: r~>,
                                           resolver: r~>,
                                           team: team,
                                           meetup: meetup,
                                           participating: participating,
                                           members: members,
                                           nonMembers: nonMembers,
                                           admin: admin)
        }
        container.register(JoinTeamViewModel.self) { r, coordinator, team in
            return JoinTeamViewModel(coordinator: coordinator,
                                      teamManager: r~>,
                                      nameSupplier: r~>,
                                      userManager: r~>,
                                      team: team)
        }

        container.register(MemberTableViewCellViewModel.self) { r, user, isTouchable, isAdmin, isSharingLocation in
            return MemberTableViewCellViewModel(nameSupplier: r~>,
                                                avatarSupplier: r~>,
                                                user: user,
                                                isTouchable: isTouchable,
                                                isAdmin: isAdmin,
                                                isSharingLocation: isSharingLocation)
        }
        container.register(LocationAnnotationDetailViewModel.self) { r, coordinator, locationAnnotation, team in
            return LocationAnnotationDetailViewModel(annotation: locationAnnotation,
                                                     team: team,
                                                     teamManager: r~>,
                                                     coordinator: coordinator,
                                                     geocoder: r~>,
                                                     addressLocalizer: r~>,
                                                     tracker: r~>)
        }
        container.register(MeetingPointAnnotation.self) { r, location in
            return MeetingPointAnnotation(addressLocalizer: r~>, location: location)
        }
        container.register(MeetingPointDetailViewModel.self) { r, coordinator, meetingPointAnnotation, team in
            return MeetingPointDetailViewModel(annotation: meetingPointAnnotation,
                                               team: team,
                                               teamManager: r~>,
                                               coordinator: coordinator,
                                               geocoder: r~>,
                                               addressLocalizer: r~>)
        }
        container.register(UserAnnotationDetailViewModel.self) { r, userAnnotation in
            return UserAnnotationDetailViewModel(annotation: userAnnotation,
                                                 avatarSupplier: r~>,
                                                 geocoder: r~>,
                                                 addressLocalizer: r~>)
        }
        container.register(DemoUserAnnotationDetailViewModel.self) { r, userAnnotation in
            return DemoUserAnnotationDetailViewModel(demoManager: r~>, geocoder: r~>, addressLocalizer: r~>, annotation: userAnnotation)
        }
        container.register(DemoMeetingPointDetailViewModel.self) { r, annotation in
            return DemoMeetingPointDetailViewModel(demoManager: r~>, geocoder: r~>, addressLocalizer: r~>, annotation: annotation)
        }
        container.register(DemoLocationAnnotationViewModel.self) { r, annotation in
            return DemoLocationAnnotationViewModel(annotation: annotation, demoManager: r~>, geocoder: r~>, addressLocalizer: r~>)
        }
        container.register(ClusterAnnotationDetailViewModel.self) { r, userAnnotation in
            return ClusterAnnotationDetailViewModel(annotation: userAnnotation, avatarSupplier: r~>, nameSupplier: r~>)
        }
        container.register(SimpleAnnotationDetailViewModel.self) { r, annotation in
            return SimpleAnnotationDetailViewModel(annotation: annotation, addressLocalizer: r~>)
        }
        container.register(TeamCellViewModel.self) { r, team, members, participationStatus in
            return TeamCellViewModel(team: team,
                                     participationStatus: participationStatus,
                                     members: members,
                                     groupStorageManager: r~>,
                                     signedInUser: r~>,
                                     nameSupplier: r~>,
                                     avatarSupplier: r~>,
                                     chatManager: r~>)
        }
        container.register(InviteViewModel.self) { r, coordinator, team in
            return InviteViewModel(nameSupplier: r~>, tracker: r~>, resolver: r~>, coordinator: coordinator, team: team)
        }
        container.register(TeamShareInvitation.self) { r, team in
            return TeamShareInvitation(nameSupplier: r~>, team: team)
        }
        container.register(ChatViewModel.self) { r, coordinator, team in
            return ChatViewModel(chatManager: r~>,
                                 teamChatDataSource: r.resolve(TeamChatDataSourceType.self, argument: team)!,
                                 chatStorageManager: r~>,
                                 userManager: r~>,
                                 avatarSupplier: r~>,
                                 nameSupplier: r~>,
                                 coordinator: coordinator,
                                 team: team)
        }
        container.register(MembershipCertificateRenewalViewModel.self) { (r, coordinator: AppFlow, signedInUser: SignedInUser) in
            let signedInUserManager = SignedInUserManagerWithUser(signedInUser: signedInUser)
            let backend = TICEBackend(api: r~>,
                                      baseURL: config.backendBaseURL,
                                      clientVersion: config.version,
                                      clientBuild: config.buildNumber,
                                      clientPlatform: config.platform,
                                      authManager: r~>,
                                      signedInUserManager: signedInUserManager)
            return MembershipCertificateRenewalViewModel(groupStorageManager: r~>,
                                         signedInUserManager: signedInUserManager,
                                         cryptoManager: r~>,
                                         authManager: r~>,
                                         backend: backend,
                                         coordinator: coordinator,
                                         encoder: r~>,
                                         certificateValidityTimeRenewalThreshold: config.certificateValidityTimeRenewalThreshold,
                                         tracker: r~>)
        }
    }
    
    private func setupSnapshot(container: Container, config: Config) {
        container.autoregister(RegisterViewModelType.self, initializer: RegisterViewModel.init).inObjectScope(.container)
    }

    private func setupSimulatorMocks(container: Container, config: Config) {
        container.autoregister(DeviceTokenManagerType.self, initializer: SimulatorDeviceTokenManager.init).inObjectScope(.container)
    }

    private func setupDebug(container: Container, config: Config) {
        container.register(RegisterFlow.self) { _, coordinator in
            return DebugRegisterCoordinator(parent: coordinator)
        }
        container.storyboardInitCompleted(DebugRegisterViewController.self) { _, _ in }
        container.register(LogViewController.self) { _ in LogViewController() }
    }
}
