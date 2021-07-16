//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import Pulley
import MapKit
import TICEAPIModels
import PromiseKit
import Swinject
import Observable
import Chatto
import AVFoundation

protocol TeamMapViewModelType: MapDelegate {
    var delegate: TeamMapViewController? { get set }
    
    var mapViewModel: MapViewModelType { get }
    var fittingMap: MutableObservable<Bool> { get }
    var showMapButtons: MutableObservable<Bool> { get }
    var following: MutableObservable<Annotation?> { get }
    var isTrackingUser: Bool { get }
    
    func viewWillAppear()
    func viewWillDisappear()
    
    func didTapStartSharing()
    func didTapSearch()
    func didTapFitMap()
    func detailViewModel(annotation: MKAnnotation) -> AnnotationDetailViewModel
    func detailViewModel(clusterAnnotation: MKClusterAnnotation) -> ClusterAnnotationDetailViewModel
    
    func follow(annotation: Annotation?)
}

class TeamMapViewController: PulleyViewController, UINavigationBarDelegate {

    @IBOutlet weak var meetupView: MeetupView!
    @IBOutlet weak var mapButtonsView: UIView!
    @IBOutlet weak var mapButtonsContainer: UIStackView!
    @IBOutlet weak var userTrackingContainer: UIView!
    @IBOutlet weak var chatWidget: ChatWidget!
    @IBOutlet weak var fitMapButton: UIButton?
    
    var userTrackingButton: MKUserTrackingButton?
    
    var mapSearchViewController: MapSearchViewController?
    
    var shouldFitAllAnnotationsOnceAnimated: Bool?
    
    var disposal = Disposal()

    var viewModel: TeamMapViewModelType! {
        didSet {
            viewModel.delegate = self
        }
    }
    
    var chatViewModel: TeamMapChatViewModelType!
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        
        initialDrawerPosition = .closed
        delegate = self
    }
    
    required init(contentViewController: UIViewController, drawerViewController: UIViewController) {
        fatalError("init(contentViewController:drawerViewController:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        mapViewController.viewModel = viewModel.mapViewModel
        mapViewController.delegate = viewModel
        mapViewController.showsUserLocation = true

        let userTrackingButton = MKUserTrackingButton(mapView: mapViewController.mapView)
        userTrackingButton.translatesAutoresizingMaskIntoConstraints = false
        userTrackingContainer.addSubview(userTrackingButton)

        NSLayoutConstraint.activate([
            userTrackingButton.centerXAnchor.constraint(equalTo: userTrackingContainer.centerXAnchor),
            userTrackingButton.centerYAnchor.constraint(equalTo: userTrackingContainer.centerYAnchor)
        ])

        self.userTrackingButton = userTrackingButton

        drawerBackgroundVisualEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        
        chatWidget.setup()
        
        chatViewModel.chatBadgeNumber.observe(.main) { [weak self] value, _ in
            self?.chatWidget.chatButton.setTitle(value > 0 ? "\(value)" : nil, for: .normal)
        }.add(to: &disposal)
        
        chatViewModel.lastMessage.observe(.main) { [weak self] message, oldMessage in
            guard message != oldMessage else { return }
            if let message = message {
                self?.show(message: message)
            } else {
                self?.hideMessage()
            }
        }.add(to: &disposal)
        
        viewModel.fittingMap.observe { [weak self] enabled, _ in
            self?.fitMapButton?.setImage(UIImage(named: enabled ? "fillOn" : "fillOff"), for: .normal)
        }.add(to: &disposal)
        viewModel.showMapButtons.observe { [weak self] show, _ in
            self?.mapButtonsView?.isHidden = !show
        }.add(to: &disposal)
        
        updateMapPadding()
        
        queueFitAllAnnotations(animated: false)
    }

    var mapViewController: MapViewController! {
        return self.primaryContentViewController as? MapViewController
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        view.bringSubviewToFront(meetupView)
        view.bringSubviewToFront(mapButtonsView)
        view.bringSubviewToFront(chatWidget)
        
        checkForQueuedAutofit()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.viewWillAppear()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        viewModel.viewWillDisappear()
    }

    @IBAction func didTapMeetup(_ sender: Any) {
        viewModel.didTapStartSharing()
    }
    
    func follow(annotation: Annotation?) {
        viewModel.follow(annotation: annotation)
    }
    
    func show(meetingPoint: Location?) {
        mapViewController.showMeetingPoint(location: meetingPoint)
    }

    func show(location: Location?, for userId: UserId) {
        mapViewController.show(location: location, for: userId)
    }
    
    @IBAction func didTapSearch(_ sender: Any) {
        viewModel.didTapSearch()
        
        let mapSearchViewController = self.mapSearchViewController ?? storyboard!.instantiateViewController(MapSearchViewController.self)
        mapSearchViewController.delegate = self
        mapSearchViewController.mapViewController = mapViewController
        self.mapSearchViewController = mapSearchViewController
        
        setDrawerContentViewController(controller: mapSearchViewController, newPosition: .open, animated: true)
    }
    
    @IBAction func didTapFitMap(_ sender: Any) {
        viewModel.didTapFitMap()
    }
    
    @IBAction func didTapCancelSearch(_ sender: Any) {
        mapSearchViewController = nil
        setDrawerContentViewController(controller: EmptyDrawerViewController(), newPosition: .closed, animated: true)
    }
    
    @IBAction func didTapChatBar(_ sender: Any) {
        chatViewModel.didTapChatBar()
    }
    
    override func makeUIAdjustmentsForFullscreen(progress: CGFloat, bottomSafeArea: CGFloat) {
        super.makeUIAdjustmentsForFullscreen(progress: progress, bottomSafeArea: bottomSafeArea)
        
        let x = clamp(progress, min: 0.0, max: 0.85)
        let normalized = minMaxNormalization(Double(x), min: 0.0, max: 0.85)
        let opacity = 1 - CGFloat(easeInOut(normalized))
        meetupView.alpha = opacity
        mapButtonsView.alpha = opacity
        chatWidget.alpha = opacity
    }
    
    override func drawerChangedDistanceFromBottom(drawer: PulleyViewController, distance: CGFloat, bottomSafeArea: CGFloat) {
        super.drawerChangedDistanceFromBottom(drawer: drawer, distance: distance, bottomSafeArea: bottomSafeArea)
        let bottom = min(view.bounds.height - distance, view.bounds.height - 6)
        
        let buttonSize = mapButtonsView.bounds.size
        mapButtonsView.frame = CGRect(x: 16, y: bottom - 32 - buttonSize.height, width: buttonSize.width, height: buttonSize.height)
        
        let chatContainerSize = chatWidget.bounds.size
        chatWidget.frame = CGRect(x: view.bounds.width - 16 - chatContainerSize.width, y: bottom - 32 - chatContainerSize.height, width: chatContainerSize.width, height: chatContainerSize.height)
    }
    
    func show(message: LastMessage) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        
        chatWidget.avatarView.transform = .init(scaleX: 2, y: 2)
        UIView.transition(with: chatWidget.avatarView,
                          duration: 0.3,
                          options: .transitionCrossDissolve,
                          animations: { [weak self] in
            self?.chatWidget.avatarView.transform = .identity
            self?.chatWidget.avatarView.image = message.avatar
            self?.chatWidget.avatarView.alpha = 1.0
        })
        
        chatWidget.setText(message.message)
        updateMapPadding()
        
        UIView.transition(with: chatWidget.messageLabel,
                          duration: 0.3,
                          options: .transitionCrossDissolve,
                          animations: { [weak self] in
                            self?.chatWidget.messageLabel.alpha = 1.0
        })
        
        UIView.transition(with: chatWidget.bubbleView,
                          duration: 0.3,
                          options: .transitionCrossDissolve,
                          animations: { [weak self] in
                            self?.chatWidget.bubbleView.alpha = 0.9
        })
    }
    
    func hideMessage() {
        UIView.transition(with: chatWidget.avatarView,
                          duration: 0.5,
                          options: .transitionCrossDissolve,
                          animations: { [weak self] in
            self?.chatWidget.avatarView.alpha = 0.0
        })
        
        UIView.transition(with: chatWidget.messageLabel,
                          duration: 0.5,
                          options: .transitionCrossDissolve,
                          animations: { [weak self] in
                            self?.chatWidget.messageLabel.alpha = 0.0
        })
        
        UIView.transition(with: chatWidget.bubbleView,
                          duration: 0.5,
                          options: .transitionCrossDissolve,
                          animations: { [weak self] in
                            self?.chatWidget.bubbleView.alpha = 0.0
        })
        
        updateMapPadding()
    }
    
    func updateMapPadding() {
        mapViewController.padding = UIEdgeInsets(top: meetupView.bounds.height + 3 * 20,
                                                 left: 60,
                                                 bottom: chatWidget.bubbleView.bounds.size.height + 3 * 20,
                                                 right: 60)
    }
    
    func fitAllAnnotations(animated: Bool) {
        mapViewController?.fitAllAnnotations(following: viewModel.following.wrappedValue, animated: animated)
    }
    
    func checkForQueuedAutofit() {
        guard let fitAllAnnotationsOnceAnimated = shouldFitAllAnnotationsOnceAnimated else {
            return
        }
        
        guard !viewModel.fittingMap.wrappedValue, viewModel.following.wrappedValue == nil, !viewModel.isTrackingUser else {
            shouldFitAllAnnotationsOnceAnimated = nil
            return
        }
        
        if mapViewController.fitAllAnnotations(following: viewModel.following.wrappedValue, animated: fitAllAnnotationsOnceAnimated) {
            shouldFitAllAnnotationsOnceAnimated = nil
        }
    }
    
    func queueFitAllAnnotations(animated: Bool) {
        self.shouldFitAllAnnotationsOnceAnimated = animated
    }
}

extension TeamMapViewController {

    func show(meetupViewModel: MeetupViewModel) {
        meetupView.viewModel = meetupViewModel
        updateMapPadding()
    }

    func showDetails(for annotation: MKAnnotation, animated: Bool) {
        let detailViewController = self.detailViewController(for: annotation)
        setDrawerContentViewController(controller: detailViewController, newPosition: .partiallyRevealed, animated: animated)
    }

    func hideDetails(animated: Bool = true) {
        mapViewController.deselectAnnotation(animated: animated)
        
        if let mapSearchViewController = self.mapSearchViewController {
            setDrawerContentViewController(controller: mapSearchViewController)
        } else {
            setDrawerPosition(position: .closed, animated: true)
        }
    }

    func remove(annotation: MKAnnotation) {
        mapViewController.remove(annotations: [annotation])
    }

    private func detailViewController(for annotation: MKAnnotation) -> UIViewController {
        switch annotation {
        case let clusterAnnotation as MKClusterAnnotation:
            // swiftlint:disable:next force_cast
            let annotationDetailViewController = storyboard!.instantiateViewController(withIdentifier: "ClusterAnnotationDetailViewController") as! ClusterAnnotationDetailViewController
            annotationDetailViewController.viewModel = viewModel.detailViewModel(clusterAnnotation: clusterAnnotation)
            return annotationDetailViewController
        default:
            // swiftlint:disable:next force_cast
            let annotationDetailViewController = storyboard!.instantiateViewController(withIdentifier: "AnnotationDetailViewController") as! AnnotationDetailViewController
            annotationDetailViewController.viewModel = viewModel.detailViewModel(annotation: annotation)
            return annotationDetailViewController
        }
    }

    func setUserTrackingMode(mode: MKUserTrackingMode) {
        userTrackingButton?.mapView?.setUserTrackingMode(mode, animated: true)
    }
}

enum MainViewModelError: LocalizedError {
    case notPermittedToUseLocation

    var errorDescription: String? {
        switch self {
        case .notPermittedToUseLocation: return L10n.MainViewModel.Error.notPermittedToUseLocation
        }
    }
}

// MARK: - View Model

class TeamMapViewModel: TeamMapViewModelType {
    
    unowned let coordinator: MainFlow

    let signedInUser: SignedInUser
    let teamManager: TeamManagerType
    let groupStorageManager: GroupStorageManagerType
    let userManager: UserManagerType
    let locationManager: LocationManagerType
    let locationSharingManager: LocationSharingManagerType
    let nameSupplier: NameSupplierType
    let avatarSupplier: AvatarSupplierType
    let notifier: Notifier
    let tracker: TrackerType
    let resolver: Swinject.Resolver
    
    var team: Team
    var ownLocationSharingState: LocationSharingState
    var othersLocationSharingState: [LocationSharingState]
    var users: [User]
    
    weak var delegate: TeamMapViewController?
    var fittingMap: MutableObservable<Bool> = .init(true)
    var showMapButtons: MutableObservable<Bool> = .init(true)
    var following: MutableObservable<Annotation?> = .init(nil)
    
    private var reloadTimer: Timer?
    
    private var teamObserverToken: ObserverToken?
    private var ownLocationSharingStateObserverToken: ObserverToken?
    private var otherLocationSharingStateObserverToken: ObserverToken?
    private var meetupObserverToken: ObserverToken?
    
    private var foregroundTransitionObserverToken: NSObjectProtocol?

    init(coordinator: MainFlow, signedInUser: SignedInUser, groupManager: TeamManagerType, groupStorageManager: GroupStorageManagerType, userManager: UserManagerType, locationManager: LocationManagerType, locationSharingManager: LocationSharingManagerType, nameSupplier: NameSupplierType, avatarSupplier: AvatarSupplierType, notificationRegistry: Notifier, tracker: TrackerType, resolver: Swinject.Resolver, group: Team, users: [User]) {
        self.coordinator = coordinator
        self.signedInUser = signedInUser
        self.teamManager = groupManager
        self.groupStorageManager = groupStorageManager
        self.userManager = userManager
        self.locationManager = locationManager
        self.locationSharingManager = locationSharingManager
        self.nameSupplier = nameSupplier
        self.avatarSupplier = avatarSupplier
        self.notifier = notificationRegistry
        self.tracker = tracker
        self.resolver = resolver
        self.team = group
        self.users = users
        self.ownLocationSharingState = locationSharingManager.locationSharingState(userId: signedInUser.userId, groupId: team.groupId)
        self.othersLocationSharingState = locationSharingManager.othersLocationSharingState(ownUserId: signedInUser.userId, groupId: team.groupId)
        
        self.notifier.register(UserLocationUpdateNotificationHandler.self, observer: self)
        
        teamObserverToken = groupStorageManager.observeTeam(groupId: team.groupId, queue: .main) { [unowned self] team, _ in
            guard let team = team else { return }
            self.team = team
            self.reloadSynchronously()
        }
        
        ownLocationSharingStateObserverToken = locationSharingManager.observeLocationSharingState(userId: self.signedInUser.userId, groupId: team.groupId, queue: .main) { [unowned self] locationSharingState in
            self.ownLocationSharingState = locationSharingState
            self.reloadSynchronously()
        }
        
        otherLocationSharingStateObserverToken = locationSharingManager.observeOthersLocationSharingState(groupId: team.groupId, queue: .main) { [unowned self] locationSharingStates in
            defer { reloadSynchronously() }
            
            let previouslySharing = othersAreLocationSharing
            othersLocationSharingState = locationSharingStates
            
            guard !ownLocationSharingState.enabled,
                  !previouslySharing else {
                return
            }
            
            if othersAreLocationSharing {
                promptForSharingLocation()
            }
        }
        
        foregroundTransitionObserverToken = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil) { [unowned self] _ in self.handleForegroundTransition() }

        teamManager.reload(team: team, reloadMeetup: true).catch({ logger.error($0) })
        
        reloadTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true, block: { [weak self] _ in
            self?.reloadSynchronously()
        })
    }
    
    private func setupMeetupObservation(meetup: Meetup) -> ObserverToken {
        groupStorageManager.observeMeetup(groupId: meetup.groupId, queue: .main) { [unowned self] _, members in
            self.users = members.map(\.user)
            self.reloadSynchronously()
        }
    }

    deinit {
        self.notifier.unregister(UserLocationUpdateNotificationHandler.self, observer: self)
        
        teamObserverToken = nil
        ownLocationSharingStateObserverToken = nil
        otherLocationSharingStateObserverToken = nil
        meetupObserverToken = nil
        
        foregroundTransitionObserverToken.map { NotificationCenter.default.removeObserver($0) }
    }
    
    var mapViewModel: MapViewModelType {
        return resolver.resolve(MapViewModel.self)!
    }

    var memberLocations: Set<MemberLocation> {
        let memberLocations: [MemberLocation] = users.map {
            let state = locationSharingManager.locationSharingState(userId: $0.userId, groupId: team.groupId)
            guard state.enabled,
                  let lastLocation = locationSharingManager.lastLocation(userId: $0.userId, groupId: team.groupId) else {
                return MemberLocation(userId: $0.userId, lastLocation: nil)
            }
            
            return MemberLocation(userId: $0.userId, lastLocation: lastLocation)
        }
        
        return Set(memberLocations)
    }

    var meetingPointLocation: Location? {
        return team.meetingPoint
    }
    
    func follow(annotation: Annotation?) {
        self.following.wrappedValue = annotation
        self.fittingMap.wrappedValue = false
        self.delegate?.setUserTrackingMode(mode: .none)
        self.delegate?.fitAllAnnotations(animated: true)
    }
    
    func viewWillAppear() {
        reloadSynchronously()
    }
    
    func viewWillDisappear() {
        delegate?.hideMessage()
    }
    
    private func reloadSynchronously() {
        guard let delegate = delegate, delegate.isViewLoaded else { return }
        
        delegate.show(meetupViewModel: meetupViewModel)
        delegate.show(meetingPoint: meetingPointLocation)

        for memberLocation in memberLocations {
            delegate.show(location: memberLocation.lastLocation, for: memberLocation.userId)
        }
    }
    
    private func reload() {
        DispatchQueue.main.async { self.reloadSynchronously() }
    }

    func didTapStartSharing() {
        if ownLocationSharingState.enabled {
            disableLocationSharing()
        } else {
            enableLocationSharing()
        }
    }
    
    func didTapFitMap() {
        tracker.log(action: .toggleFittingMap, category: .app)
        following.wrappedValue = nil
        fittingMap.wrappedValue.toggle()
        
        if fittingMap.wrappedValue {
            delegate?.setUserTrackingMode(mode: .none)
            delegate?.mapViewController.fitAllAnnotations(following: following.wrappedValue, animated: true)
        }
    }
    
    func didTapSearch() {
        tracker.log(action: .showMapSearch, category: .app)
    }
    
    func detailViewModel(annotation: MKAnnotation) -> AnnotationDetailViewModel {
        switch annotation {
        case let userLocation as MKUserLocation:
            let user = resolver.resolve(SignedInUser.self)! as User
            let location = userLocation.location!
            let alwaysUpToDate = true
            let userAnnotation = resolver.resolve(UserAnnotation.self, arguments: location, user, alwaysUpToDate)!
            let userAnnotationDetailViewModel = resolver.resolve(UserAnnotationDetailViewModel.self, argument: userAnnotation)!
            userAnnotationDetailViewModel.delegate = delegate
            return userAnnotationDetailViewModel
        case let locationAnnotation as LocationAnnotation:
            let locationAnnotationDetailViewModel = resolver.resolve(LocationAnnotationDetailViewModel.self, arguments: coordinator, locationAnnotation, team)!
            locationAnnotationDetailViewModel.delegate = delegate
            return locationAnnotationDetailViewModel
        case let meetingPointAnnotation as MeetingPointAnnotation:
            let viewModel = resolver.resolve(MeetingPointDetailViewModel.self, arguments: coordinator, meetingPointAnnotation, team)!
            viewModel.delegate = delegate
            return viewModel
        case let userAnnotation as UserAnnotation:
            let userAnnotationDetailViewModel = resolver.resolve(UserAnnotationDetailViewModel.self, argument: userAnnotation)!
            userAnnotationDetailViewModel.delegate = delegate
            return userAnnotationDetailViewModel
        default:
            let simpleAnnotationDetailViewModel = resolver.resolve(SimpleAnnotationDetailViewModel.self, argument: annotation)!
            simpleAnnotationDetailViewModel.delegate = delegate
            return simpleAnnotationDetailViewModel
        }
    }
    
    func detailViewModel(clusterAnnotation: MKClusterAnnotation) -> ClusterAnnotationDetailViewModel {
        let clusterAnnotationDetailViewModel = resolver.resolve(ClusterAnnotationDetailViewModel.self, argument: clusterAnnotation)!
        clusterAnnotationDetailViewModel.delegate = delegate
        return clusterAnnotationDetailViewModel
    }
    
    func showDetails(for annotation: MKAnnotation) {
        delegate?.showDetails(for: annotation, animated: true)
    }
    
    func hideDetails() {
        delegate?.hideDetails(animated: true)
    }
    
    func handleUserTrackingModeChange(mode: MKUserTrackingMode) {
        tracker.log(action: .toggleUserTracking, category: .app)
        
        guard mode != .none else {
            return
        }
        
        following.wrappedValue = nil
        fittingMap.wrappedValue = false
        
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestLocationAuthorization()
        case .notAuthorized:
            coordinator.show(error: MainViewModelError.notPermittedToUseLocation)
            delegate?.setUserTrackingMode(mode: .none)
        case .authorized:
            break
        }
    }
    
    func enableLocationSharing() {
        firstly {
            coordinator.askForUserConfirmation(title: L10n.Team.StartLocationSharing.title,
                                               message: L10n.Team.StartLocationSharing.message)
        }.then {
            self.teamManager.setLocationSharing(in: self.team, enabled: true)
        }.catch { error in
            if (error as? TeamManagerError) == .notAuthorizedToUseLocation {
                let error = L10n.Error.TeamManager.LocationSharing.NotAuthorized.self
                firstly {
                    self.coordinator.askForUserConfirmation(title: error.title, message: error.message, action: error.openSettings)
                }.done {
                    UIApplication.openSettings()
                }.cauterize()
            } else {
                self.coordinator.show(error: error)
            }
        }
    }
    
    func disableLocationSharing() {
        firstly {
            coordinator.askForUserConfirmation(title: L10n.Team.StopLocationSharing.title,
                                               message: L10n.Team.StopLocationSharing.message)
        }.then {
            self.teamManager.setLocationSharing(in: self.team, enabled: false)
        }.catch { error in
            self.coordinator.show(error: error)
        }
    }
    
    func handleManualRegionChange() {
        fittingMap.wrappedValue = false
        following.wrappedValue = nil
    }
    
    var isTrackingUser: Bool {
        guard let userTrackingMode = delegate?.userTrackingButton?.mapView?.userTrackingMode else {
            return false
        }
        
        return userTrackingMode != .none
    }
    
    func handleUserLocationUpdate() {
        guard !isTrackingUser else { return }
        
        if fittingMap.wrappedValue {
            delegate?.fitAllAnnotations(animated: true)
        } else {
            delegate?.checkForQueuedAutofit()
        }
    }
    
    private func promptForSharingLocation() {
        let users = othersLocationSharingState.filter { $0.enabled }.compactMap { userManager.user($0.userId) }
        let names = users.map { nameSupplier.name(user: $0) }
        let allNames = LocalizedList(names)
        
        let title = L10n.Notification.LocationSharing.OthersSharing.InApp.title
        let Body = L10n.Notification.LocationSharing.OthersSharing.InApp.Body.self
        let body = names.count > 1 ? Body.plural(allNames) : Body.singular(allNames)
        
        firstly {
            self.coordinator.askForUserConfirmation(title: title,
                                                    message: body,
                                                    action: L10n.Notification.LocationSharing.OthersSharing.InApp.join,
                                                    cancel: L10n.Notification.LocationSharing.OthersSharing.InApp.cancel)
        }.done {
            self.reloadSynchronously()
        }.then {
            self.teamManager.setLocationSharing(in: self.team, enabled: true)
        }.catch { error in
            if (error as? TeamManagerError) == .notAuthorizedToUseLocation {
                let error = L10n.Error.TeamManager.LocationSharing.NotAuthorized.self
                firstly {
                    self.coordinator.askForUserConfirmation(title: error.title, message: error.message, action: error.openSettings)
                }.done {
                    UIApplication.openSettings()
                }.cauterize()
            } else {
                self.coordinator.show(error: error)
            }
        }.finally {
            self.reloadSynchronously()
        }
    }
    
    @objc
    private func handleForegroundTransition() {
        do {
            guard let team = try groupStorageManager.loadTeam(team.groupId) else {
                DispatchQueue.main.async { self.coordinator.didLeaveOrDeleteTeam() }
                return
            }
            self.team = team
            self.users = try groupStorageManager.members(groupId: team.groupId).map(\.user)
            
            reload()
        } catch {
            logger.error("Error reloading data after transition to foreground: \(error)")
        }
    }
}

extension TeamMapViewModel: LocationAuthorizationStatusChangeHandler {
    func authorizationStatusChanged(to status: LocationAuthorizationStatus) {
        if status != .authorized {
            delegate?.setUserTrackingMode(mode: .none)
        }
    }
}

extension TeamMapViewModel: UserLocationUpdateNotificationHandler {
    func didUpdateLocation(userId: UserId) {
        DispatchQueue.main.async {
            defer {
                if self.fittingMap.wrappedValue || self.following.wrappedValue != nil {
                    self.delegate?.fitAllAnnotations(animated: true)
                }
            }
            
            guard let user = self.users.first(where: { $0.userId == userId }) else {
                logger.debug("Updated location does not belong to user in team.")
                return
            }

            guard let lastLocation = self.locationSharingManager.lastLocation(userId: user.userId, groupId: self.team.groupId) else {
                logger.debug("Member has no last location. Removing annotation.")
                self.delegate?.show(location: nil, for: user.userId)
                return
            }

            self.delegate?.show(location: lastLocation, for: user.userId)
            logger.debug("Did update location for member \(userId).")
        }
    }
}

extension TeamMapViewModel {
    var meetupViewModel: MeetupViewModel {
        return MeetupViewModel(visible: true,
                               title: meetupButtonTitle,
                               titleColor: meetupButtonTitleColor,
                               description: meetupButtonDescription,
                               descriptionColor: meetupButtonDescriptionColor,
                               backgroundColor: meetupButtonBackgroundColor,
                               iconImage: meetupIcon,
                               showDisclosureIndicator: meetupButtonShowDisclosureIndicator)
    }

    private var meetupButtonBackgroundColor: UIColor {
        return .highlightBackground
    }

    private var meetupButtonTitleColor: UIColor {
        return .white
    }

    private var meetupButtonDescriptionColor: UIColor {
        return .lightText
    }
    
    private var othersAreLocationSharing: Bool {
        othersLocationSharingState.contains(where: { $0.enabled })
    }

    private var meetupButtonTitle: String {
        if ownLocationSharingState.enabled {
            return L10n.Team.LocationSharing.Active.title
        } else if othersAreLocationSharing {
            return L10n.Team.LocationSharing.OthersActive.title
        } else {
            return L10n.Team.LocationSharing.Start.title
        }
    }

    private var meetupButtonDescription: String? {
        if ownLocationSharingState.enabled {
            return L10n.Team.LocationSharing.Active.subtitle
        } else if othersAreLocationSharing {
            let count = othersLocationSharingState.reduce(0) { last, now in now.enabled ? last + 1 : last }
            if count == 1,
               let locationSharingState = othersLocationSharingState.first(where: { $0.enabled }),
               let user = userManager.user(locationSharingState.userId) {
                let name = nameSupplier.name(user: user)
                return L10n.Team.LocationSharing.OtherActive.subtitle(name)
            } else {
                return L10n.Team.LocationSharing.OthersActive.subtitle
            }
        } else {
            return nil
        }
    }
    
    private var meetupIcon: UIImage? {
        if ownLocationSharingState.enabled {
            return UIImage(named: "tracking")
        } else if othersAreLocationSharing {
            return UIImage(named: "invited")
        } else {
            return nil
        }
    }

    private var meetupButtonShowDisclosureIndicator: Bool {
        return ownLocationSharingState.enabled || othersAreLocationSharing
    }
}
