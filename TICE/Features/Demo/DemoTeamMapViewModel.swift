//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import MapKit
import CoreLocation
import PromiseKit
import Observable
import Swinject
import TICEAPIModels

class DemoTeamMapViewModel: TeamMapViewModelType {

    let demoManager: DemoManagerType
    let signedInUser: SignedInUser
    let notifier: Notifier
    let resolver: Swinject.Resolver
    
    let coordinator: DemoFlow
    
    weak var delegate: TeamMapViewController?
    
    var fittingMap: MutableObservable<Bool> = .init(false)
    var showMapButtons: MutableObservable<Bool> = .init(false)
    var following: MutableObservable<Annotation?> = .init(nil)
    var isTrackingUser: Bool = false
    
    var mapViewModel: MapViewModelType {
        return resolver.resolve(MapViewModel.self)!
    }
    
    var meetupViewModel: MeetupViewModel {
        let demoTeam = demoManager.demoTeam.wrappedValue
        return MeetupViewModel(visible: demoManager.showMeetupButton.wrappedValue,
                               title: demoTeam.userSharingLocation ? L10n.Team.LocationSharing.Active.title : L10n.Team.LocationSharing.OthersActive.title,
                               titleColor: .white,
                               description: demoTeam.userSharingLocation ? L10n.Team.LocationSharing.Active.subtitle : L10n.Team.LocationSharing.OthersActive.subtitle,
                               descriptionColor: .lightText,
                               backgroundColor: .highlightBackground,
                               iconImage: demoTeam.userSharingLocation ? UIImage(named: "tracking") : UIImage(named: "invited"),
                               showDisclosureIndicator: true)
    }
    
    var timer: Timer?
    
    var othersLocationSharingObserverToken: ObserverToken?
    var disposal = Disposal()
    
    init(demoManager: DemoManagerType, signedInUser: SignedInUser, notifier: Notifier, resolver: Swinject.Resolver, coordinator: DemoFlow) {
        self.demoManager = demoManager
        self.signedInUser = signedInUser
        self.notifier = notifier
        self.resolver = resolver
        self.coordinator = coordinator
        
        self.timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [unowned self] _ in
            self.updateLocations()
        }
        
        demoManager.locationSharingStates.observe(.main) { [weak self] states, _ in
            self?.didUpdateOthersLocationSharingState(states: states)
        }.add(to: &disposal)
        
        demoManager.showMeetupButton.observe(.main) { [weak self] _, _ in
            guard let self = self else { return }
            self.delegate?.show(meetupViewModel: self.meetupViewModel)
        }.add(to: &disposal)
        
        demoManager.demoTeam.observe(.main) { [weak self] team, _ in
            let meetingPoint = team.meetingPoint.map { Location(latitude: $0.latitude, longitude: $0.longitude) }
            self?.delegate?.show(meetingPoint: meetingPoint)
        }.add(to: &disposal)
        
        self.notifier.register(UserLocationUpdateNotificationHandler.self, observer: self)
    }
    
    deinit {
        timer?.invalidate()
        
        othersLocationSharingObserverToken = nil
        notifier.unregister(UserLocationUpdateNotificationHandler.self, observer: self)
    }
    
    func viewWillAppear() {
        updateLocations()
    }
    
    func viewWillDisappear() {

    }
    
    func didTapStartSharing() {
        if demoManager.demoTeam.wrappedValue.userSharingLocation {
            // stop location sharing
            self.demoManager.didEndLocationSharing()
            self.updateLocations()
        } else {
            firstly {
                coordinator.askForUserConfirmation(title: L10n.Demo.Team.ConfirmLocationSharing.title, message: L10n.Demo.Team.ConfirmLocationSharing.body)
            }.done {
                self.demoManager.didStartLocationSharing()
                self.updateLocations()
                self.delegate?.mapViewController.fitAllAnnotations(following: nil, animated: true)
            }.catch { error in
                self.coordinator.show(error: error)
            }
        }
    }
    
    var memberLocations: Set<MemberLocation> {
        return demoManager.memberLocations
    }
    
    func didTapSearch() {
        
    }
    
    func didTapFitMap() {
        
    }
    
    func follow(annotation: Annotation?) {
        
    }
    
    func detailViewModel(annotation: MKAnnotation) -> AnnotationDetailViewModel {
        var viewModel: AnnotationDetailViewModel
        switch annotation {
        case let userLocation as MKUserLocation:
            let user = resolver.resolve(SignedInUser.self)! as User
            let location = userLocation.location!
            let alwaysUpToDate = true
            let userAnnotation = resolver.resolve(UserAnnotation.self, arguments: location, user, alwaysUpToDate)!
            viewModel = resolver.resolve(UserAnnotationDetailViewModel.self, argument: userAnnotation)!
        case let userAnnotation as UserAnnotation:
            viewModel = resolver.resolve(UserAnnotationDetailViewModel.self, argument: userAnnotation)!
        case let locationAnnotation as LocationAnnotation:
            viewModel = resolver.resolve(DemoLocationAnnotationViewModel.self, argument: locationAnnotation)!
        case let userAnnotation as DemoUserAnnotation:
            viewModel = resolver.resolve(DemoUserAnnotationDetailViewModel.self, argument: userAnnotation)!
        case let meetingPointAnnotation as MeetingPointAnnotation:
            viewModel = resolver.resolve(DemoMeetingPointDetailViewModel.self, argument: meetingPointAnnotation)!
        default:
            viewModel = resolver.resolve(SimpleAnnotationDetailViewModel.self, argument: annotation)!
        }
        viewModel.delegate = delegate
        return viewModel
    }
    
    func detailViewModel(clusterAnnotation: MKClusterAnnotation) -> ClusterAnnotationDetailViewModel {
        let viewModel = resolver.resolve(ClusterAnnotationDetailViewModel.self, argument: clusterAnnotation)!
        viewModel.delegate = delegate
        return viewModel
    }
    
    func updateLocations() {
        for memberLocation in memberLocations {
            delegate?.show(location: memberLocation.lastLocation, for: memberLocation.userId)
        }
    }
    
    func didUpdateOthersLocationSharingState(states: [LocationSharingState]) {
        states.forEach { state in
            let userId = state.userId
            let lastLocation = self.demoManager.lastLocation(userId: userId)
            self.delegate?.show(location: lastLocation, for: userId)
            logger.debug("Did update location sharing for member \(userId).")
        }
        
        self.delegate?.fitAllAnnotations(animated: true)
    }
}

extension DemoTeamMapViewModel: UserLocationUpdateNotificationHandler {
    func didUpdateLocation(userId: UserId) {
        DispatchQueue.main.async {
            let lastLocation = self.demoManager.lastLocation(userId: userId)
            self.delegate?.show(location: lastLocation, for: userId)
            logger.debug("Did update location for member \(userId).")

            if self.fittingMap.wrappedValue {
                self.delegate?.fitAllAnnotations(animated: true)
            }
        }
    }
}

extension DemoTeamMapViewModel: MapDelegate {
    func showDetails(for annotation: MKAnnotation) {
        delegate?.showDetails(for: annotation, animated: true)
        
        if let demoUserAnnotation = annotation as? DemoUserAnnotation {
            demoManager.didSelectUser(user: demoUserAnnotation.user)
        }
    }
    
    func hideDetails() {
        delegate?.hideDetails(animated: true)
        demoManager.didHideAnnotation()
    }
    
    func handleUserTrackingModeChange(mode: MKUserTrackingMode) {
        
    }
    
    func handleManualRegionChange() {
        fittingMap.wrappedValue = false
    }
    
    func handleUserLocationUpdate() {
        guard let delegate = delegate else { return }
        let mapView = delegate.mapViewController.mapView!
        let coordinate = mapView.userLocation.location?.coordinate ?? mapView.centerCoordinate
        demoManager.lastLocation = Coordinate(coordinate)
    }
}
