//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import MapKit
import Pulley
import TICEAPIModels
import Swinject

protocol MapViewControllerType: AnyObject {
    
    var mapView: MKMapView! { get }
    
    var showsUserLocation: Bool { get set }

    func fit(annotations: [MKAnnotation], includeUserLocation: Bool, animated: Bool)
    func show(location: Location?, for userId: UserId)
    func show(newAnnotation annotation: LocationAnnotation)
    func showMeetingPoint(location: Location?)

    func add(annotations: [MKAnnotation])
    func remove(annotations: [MKAnnotation])
    
    func removeMeetupAnnotations()
    func removeMeetupOverlays()
    
    @discardableResult
    func fitAllAnnotations(following: Annotation?, animated: Bool) -> Bool
    
    func deselectAnnotation(animated: Bool)
}

protocol MapDelegate: AnyObject {
    func showDetails(for annotation: MKAnnotation)
    func hideDetails()
    func handleUserTrackingModeChange(mode: MKUserTrackingMode)
    func handleManualRegionChange()
    func handleUserLocationUpdate()
}

class MapViewController: UIViewController {

    @IBOutlet var longPressGestureRecognizer: UILongPressGestureRecognizer!
    @IBOutlet var mapView: MKMapView!
    
    var viewModel: MapViewModelType! {
        didSet {
            viewModel.delegate = self
        }
    }

    weak var delegate: MapDelegate?
    
    var padding: UIEdgeInsets = .zero
    var lastAnnotation: MKAnnotation?
    
    private var mapRegionIsAnimating: Bool = false
    private var ignoreRegionChange: Bool = true
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        mapView.register(UserAnnotationView.self, forAnnotationViewWithReuseIdentifier: "user")
        mapView.register(DemoUserAnnotationView.self, forAnnotationViewWithReuseIdentifier: "demoUser")
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "meetingPoint")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.enter()
        
        ignoreRegionChange = true
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        ignoreRegionChange = false
    }

    @IBAction func didLongPress(gestureRecognizer: UIGestureRecognizer) {
        guard gestureRecognizer.state == .began else { return }
        
        let touchPoint = gestureRecognizer.location(in: mapView)
        let newCoordinates = mapView.convert(touchPoint, toCoordinateFrom: mapView)
        let location = CLLocation(latitude: newCoordinates.latitude, longitude: newCoordinates.longitude)
        let annotation = viewModel.locationAnnotation(location: location)
        show(newAnnotation: annotation)
    }

    func show(newAnnotation annotation: LocationAnnotation) {
        if let lastAnnotation = lastAnnotation {
            mapView.removeAnnotation(lastAnnotation)
        }

        lastAnnotation = annotation

        mapView.addAnnotation(annotation)
        mapView.selectAnnotation(annotation, animated: true)
    }

    func remove(annotations: [MKAnnotation]) {
        mapView.removeAnnotations(annotations)
    }
    
    func fit(annotations: [MKAnnotation], includeUserLocation: Bool, animated: Bool) {
        var annotations = annotations
        
        if includeUserLocation && viewModel.showUserLocation {
            annotations.append(mapView.userLocation)
        }
        
        ignoreRegionChange = true
        mapView.showAnnotations(annotations, animated: animated)
        ignoreRegionChange = false
    }

    func fittingMapRect(annotations: [MKAnnotation]) -> MKMapRect? {
        let coordinates = annotations.map { $0.coordinate }

        guard !coordinates.isEmpty else {
            return nil
        }

        return coordinates.makeRect()!
    }

    func annotation(for userId: UserId) -> Annotation? {
        return mapView.annotations.first { annotation in
            if let annotation = annotation as? UserAnnotation {
                return annotation.user.userId == userId
            } else if let annotation = annotation as? DemoUserAnnotation {
                return annotation.user.userId == userId
            } else {
                return false
            }
        } as? Annotation
    }

    func removeMeetupAnnotations() {
        mapView.removeAnnotations(mapView.annotations.filter {
            return !($0 is LocationAnnotation)
        })
    }

    func removeMeetupOverlays() {
        for annotation in mapView.annotations {
            if let annotation = annotation as? UserAnnotation,
                let accuracyCircle = annotation.attachedAccuracyCircle {
                mapView.removeOverlay(accuracyCircle)
            }
        }
    }

    var meetingPointAnnotation: MeetingPointAnnotation? {
        return mapView.annotations.first { annotation in
            return annotation is MeetingPointAnnotation
        } as? MeetingPointAnnotation
    }
}

extension MapViewController: MapViewControllerType {
    
    func add(annotations: [MKAnnotation]) {
        mapView.addAnnotations(annotations)
    }
    
    var showsUserLocation: Bool {
        get { return mapView.showsUserLocation }
        set { mapView.showsUserLocation = newValue }
    }

    @discardableResult
    func fitAllAnnotations(following: Annotation?, animated: Bool) -> Bool {
        guard !(animated && mapRegionIsAnimating) else { return false }
        
        if showsUserLocation {
            guard let userLocation = mapView.userLocation.location,
                  userLocation.coordinate.latitude != 0 || userLocation.coordinate.longitude != 0 else {
                return false
            }
        }
        
        let annotations = following != nil ? [following!] : mapView.annotations
        guard let newMapRect = fittingMapRect(annotations: annotations) else {
            let regionRect = viewModel.regionCoordinates().makeRect()!
            ignoreRegionChange = true
            mapView.setVisibleMapRect(regionRect, edgePadding: padding, animated: animated)
            ignoreRegionChange = false
            return false
        }
        
        let visibleMapRect = mapView.visibleMapRect
        let newFittedMapRect = mapView.mapRectThatFits(newMapRect, edgePadding: padding)
        let sizeRatio = max(visibleMapRect.width * visibleMapRect.height, 1) / max(newFittedMapRect.width * newFittedMapRect.height, 1)
        let sizeRatioChangeInThreshold = (0.8...1.2).contains(sizeRatio)
        
        if visibleMapRect.contains(newMapRect) && sizeRatioChangeInThreshold { return false }
        
        ignoreRegionChange = true
        mapView.setVisibleMapRect(newMapRect.zoomed(minimumZoom: 1000), edgePadding: padding, animated: animated)
        ignoreRegionChange = false
        return true
    }

    func show(location: Location?, for userId: UserId) {
        if let annotation = annotation(for: userId) {
            if let overlay = annotation.attachedAccuracyCircle {
                mapView.removeOverlay(overlay)
            }

            guard let location = location else {
                mapView.removeAnnotation(annotation)
                return
            }

            let overlay = MKCircle(center: location.coordinate, radius: location.horizontalAccuracy)
            annotation.attachedAccuracyCircle = overlay
            self.mapView.addOverlay(overlay)

            UIView.animate(withDuration: 0.5) {
                annotation.location = CLLocation(location)
            }
        } else if let location = location {
            logger.debug("No annotation for that user on the map yet. Creating one.")
            let userAnnotation = viewModel.annotation(for: userId, location: CLLocation(location))
            mapView.addAnnotation(userAnnotation)

            let overlay = MKCircle(center: location.coordinate, radius: location.horizontalAccuracy)
            userAnnotation.attachedAccuracyCircle = overlay
            mapView.addOverlay(overlay)
        }
    }

    func showMeetingPoint(location: Location?) {
        if let annotation = meetingPointAnnotation {
            guard let location = location else {
                mapView.removeAnnotation(annotation)
                return
            }

            UIView.animate(withDuration: 0.5) {
                annotation.location = CLLocation(location)
            }
        } else {
            if let lastAnnotation = self.lastAnnotation, lastAnnotation.coordinate == location?.coordinate {
                self.remove(annotations: [lastAnnotation])
            }
            
            guard let location = location else {
                return
            }

            logger.debug("No annotation for that meeting point on the map yet. Creating one.")
            let meetingPointAnnotation = viewModel.meetingPointAnnotation(location: CLLocation(location))
            mapView.addAnnotation(meetingPointAnnotation)
        }
    }

    func deselectAnnotation(animated: Bool = true) {
        mapView.deselectAnnotation(nil, animated: animated)
    }
}

extension MapViewController: PulleyPrimaryContentControllerDelegate {
    func drawerChangedDistanceFromBottom(drawer: PulleyViewController, distance: CGFloat, bottomSafeArea: CGFloat) {
        let mapView: MKMapView = self.mapView
        let bottomInset = max(min(distance - bottomSafeArea, 169 + bottomSafeArea + 28), -28)
        mapView.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
    }
}

extension MapViewController: MKMapViewDelegate {

    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        guard let annotation = view.annotation else {
            logger.warning("Annotation view \(view) was selected but it has no annotation attached.")
            return
        }

        delegate?.showDetails(for: annotation)
    }

    func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
        delegate?.hideDetails()
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation {
            return nil
        }

        if let userAnnotation = annotation as? UserAnnotation {
            // swiftlint:disable:next force_cast
            let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: "user", for: userAnnotation) as! UserAnnotationView
            annotationView.viewModel = viewModel.viewModel(userAnnotation: userAnnotation)
            return annotationView
        }
        
        if let demoUserAnnotation = annotation as? DemoUserAnnotation {
            // swiftlint:disable:next force_cast
            let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: "demoUser", for: demoUserAnnotation) as! DemoUserAnnotationView
            annotationView.viewModel = viewModel.viewModel(demoUserAnnotation: demoUserAnnotation)
            return annotationView
        }

        if let meetingPointAnnotation = annotation as? MeetingPointAnnotation {
            // swiftlint:disable:next force_cast
            let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: "meetingPoint", for: meetingPointAnnotation) as! MKMarkerAnnotationView
            annotationView.markerTintColor = .highlight
            annotationView.displayPriority = .required
            return annotationView
        }

        if let clusterAnnotation = annotation as? MKClusterAnnotation {
            let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier, for: clusterAnnotation)
            annotationView.displayPriority = .required
            return annotationView
        }

        if let locationAnnotation = annotation as? LocationAnnotation {
            let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier, for: locationAnnotation)
            annotationView.displayPriority = .required
            return annotationView
        }

        return nil
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let circle = overlay as? MKCircle {
            let renderer = MKCircleRenderer(circle: circle)
            renderer.fillColor = UIColor.highlightBackground.withAlphaComponent(0.2)
            return renderer
        }

        return MKOverlayRenderer(overlay: overlay)
    }

    func mapView(_ mapView: MKMapView, didChange mode: MKUserTrackingMode, animated: Bool) {
        delegate?.handleUserTrackingModeChange(mode: mode)
    }
    
    func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
        mapRegionIsAnimating = animated
        guard !ignoreRegionChange else { return }
        delegate?.handleManualRegionChange()
    }
    
    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        mapRegionIsAnimating = false
    }
    
    func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
        delegate?.handleUserLocationUpdate()
    }
}

extension CLLocationCoordinate2D: Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

protocol MapViewModelType {
    var delegate: MapViewController? { get set }
    var showUserLocation: Bool { get }
    
    func enter()
    func viewModel(userAnnotation: UserAnnotation) -> UserAnnotationViewModel
    func viewModel(demoUserAnnotation: DemoUserAnnotation) -> DemoUserAnnotationViewModel
    func annotation(for userId: UserId, location: CLLocation) -> Annotation
    func meetingPointAnnotation(location: CLLocation) -> MeetingPointAnnotation
    func locationAnnotation(location: CLLocation) -> LocationAnnotation
    func regionCoordinates() -> [CLLocationCoordinate2D]
}

class MapViewModel: MapViewModelType {
    
    let userManager: UserManagerType
    let locationManager: LocationManagerType
    let nameSupplier: NameSupplierType
    let avatarSupplier: AvatarSupplierType
    let avatarGenerator: AvatarGeneratorType
    let demoManager: DemoManagerType
    let regionGeocoder: RegionGeocoderType
    let resolver: Resolver
    
    weak var delegate: MapViewController?
    
    init(userManager: UserManagerType, locationManager: LocationManagerType, nameSupplier: NameSupplierType, avatarSupplier: AvatarSupplierType, avatarGenerator: AvatarGeneratorType, demoManager: DemoManagerType, regionGeocoder: RegionGeocoderType, resolver: Resolver) {
        self.userManager = userManager
        self.locationManager = locationManager
        self.nameSupplier = nameSupplier
        self.avatarSupplier = avatarSupplier
        self.avatarGenerator = avatarGenerator
        self.demoManager = demoManager
        self.regionGeocoder = regionGeocoder
        self.resolver = resolver
    }
    
    var showUserLocation: Bool { locationManager.authorizationStatus == .authorized }
    
    func enter() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestLocationAuthorization()
        }
    }
    
    func viewModel(userAnnotation: UserAnnotation) -> UserAnnotationViewModel {
        let name = nameSupplier.name(user: userAnnotation.user)
        let initials = avatarGenerator.extractLetters(name: name)
        let color = avatarGenerator.generateColor(userId: userAnnotation.user.userId)
        return UserAnnotationViewModel(name: name, initials: initials, color: color)
    }
    
    func viewModel(demoUserAnnotation: DemoUserAnnotation) -> DemoUserAnnotationViewModel {
        let size = CGSize(width: 48, height: 48)
        let image = demoManager.avatar(demoUser: demoUserAnnotation.user).resized(to: size)
        let name = demoUserAnnotation.user.name
        return DemoUserAnnotationViewModel(image: image, name: name)
    }
    
    func annotation(for userId: UserId, location: CLLocation) -> Annotation {
        if let user = userManager.user(userId) {
            let alwaysUpToDate = false
            return resolver.resolve(UserAnnotation.self, arguments: location, user, alwaysUpToDate)!
        }
        
        if let demoUser = demoManager.demoUser(userId: userId) {
            return resolver.resolve(DemoUserAnnotation.self, arguments: location, demoUser)!
        }
        
        fatalError()
    }
    
    func meetingPointAnnotation(location: CLLocation) -> MeetingPointAnnotation {
        return resolver.resolve(MeetingPointAnnotation.self, argument: location)!
    }
    
    func locationAnnotation(location: CLLocation) -> LocationAnnotation {
        return resolver.resolve(LocationAnnotation.self, argument: location)!
    }
    
    func regionCoordinates() -> [CLLocationCoordinate2D] {
        let boundingBox = regionGeocoder.currentLocaleRegion()
        return boundingBox.coordinateArray()
    }
}
