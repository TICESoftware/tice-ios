//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import Pulley
import CoreLocation
import MapKit
import PromiseKit
import Observable
import Contacts

class EmptyDrawerViewController: UIViewController, PulleyDrawerViewControllerDelegate {
    
}

class AnnotationDetailViewController: UIViewController, PulleyDrawerViewControllerDelegate {

    var viewModel: AnnotationDetailViewModel!
    var disposal: Disposal = Disposal()
    var timer: Timer?

    @IBOutlet weak var containerView: UIView!
    
    @IBOutlet weak var avatarView: UIImageView!

    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var descriptionLabel: UILabel!
    @IBOutlet weak var closeButton: UIButton!

    @IBOutlet weak var primaryButton: UIButton!
    @IBOutlet weak var secondaryButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()

        viewModel.title.observe(.main) { [weak self] value, _ in self?.titleLabel.text = value }.add(to: &disposal)
        viewModel.description.observe(.main) { [weak self] value, _ in self?.descriptionLabel.text = value }.add(to: &disposal)
        viewModel.closeButtonVisible.observe(.main) { [weak self] value, _ in self?.closeButton.isHidden = !value }.add(to: &disposal)

        viewModel.avatar.observe(.main) { [weak self] value, _ in
            self?.avatarView.isHidden = value == nil
            self?.avatarView.image = value
        }.add(to: &disposal)

        viewModel.primaryButtonTitle.observe(.main) { [weak self] value, _ in
            self?.primaryButton.setTitle(value, for: .normal)
        }.add(to: &disposal)
        viewModel.primaryButtonEnabled.observe(.main) { [weak self] value, _ in
            self?.primaryButton.isEnabled = value
            self?.primaryButton.backgroundColor = value ? UIColor.highlightBackground : UIColor.lightGray
        }.add(to: &disposal)
        self.primaryButton.isHidden = !viewModel.primaryButtonVisible.wrappedValue
        viewModel.primaryButtonVisible.observe(.main) { [weak self] value, _ in
            self?.primaryButton.isHidden = !value
        }.add(to: &disposal)

        viewModel.secondaryButtonTitle.observe(.main) { [weak self] value, _ in
            self?.secondaryButton.setTitle(value, for: .normal)
        }.add(to: &disposal)
        viewModel.secondaryButtonEnabled.observe(.main) { [weak self] value, _ in
            self?.secondaryButton.isEnabled = value
        }.add(to: &disposal)
        self.secondaryButton.isHidden = !viewModel.secondaryButtonVisible.wrappedValue
        viewModel.secondaryButtonVisible.observe(.main) { [weak self] value, _ in
            self?.secondaryButton.isHidden = !value
        }.add(to: &disposal)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        viewModel.update()
        
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.viewModel.update()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        timer?.invalidate()
        timer = nil
    }

    func supportedDrawerPositions() -> [PulleyPosition] {
        return [.closed, .partiallyRevealed]
    }

    func partialRevealDrawerHeight(bottomSafeArea: CGFloat) -> CGFloat {
        return 169 + bottomSafeArea
    }

    @IBAction func closeButtonTapped(_ sender: Any) {
        viewModel.close()
    }

    @IBAction func primaryButtonTapped(_ sender: Any) {
        viewModel.primaryAction()
    }

    @IBAction func secondaryButtonTapped(_ sender: Any) {
        viewModel.secondaryAction()
    }
}

protocol AnnotationDetailViewModel {

    var title: MutableObservable<String> { get }
    var description: MutableObservable<String> { get }
    var closeButtonVisible: MutableObservable<Bool> { get }

    var avatar: MutableObservable<UIImage?> { get }

    var primaryButtonTitle: MutableObservable<String> { get }
    var primaryButtonEnabled: MutableObservable<Bool> { get }
    var primaryButtonVisible: MutableObservable<Bool> { get }

    var secondaryButtonTitle: MutableObservable<String> { get }
    var secondaryButtonEnabled: MutableObservable<Bool> { get }
    var secondaryButtonVisible: MutableObservable<Bool> { get }

    var delegate: TeamMapViewController? { get set }

    func update()

    func close()
    func hide()

    func primaryAction()
    func secondaryAction()
}

class SimpleAnnotationDetailViewModel: AnnotationDetailViewModel {
    
    var annotation: MKAnnotation
    let addressLocalizer: AddressLocalizerType
    
    weak var delegate: TeamMapViewController?

    var title: MutableObservable<String>
    var description: MutableObservable<String>
    var closeButtonVisible: MutableObservable<Bool>

    var avatar: MutableObservable<UIImage?>

    var primaryButtonTitle: MutableObservable<String>
    var primaryButtonEnabled: MutableObservable<Bool>
    var primaryButtonVisible: MutableObservable<Bool>

    var secondaryButtonTitle: MutableObservable<String>
    var secondaryButtonEnabled: MutableObservable<Bool>
    var secondaryButtonVisible: MutableObservable<Bool>

    init(annotation: MKAnnotation, addressLocalizer: AddressLocalizerType) {
        self.annotation = annotation
        self.addressLocalizer = addressLocalizer

        title = .init(annotation.title.flatMap { $0 } ?? L10n.SimpleAnnotationDetail.Title.default)
        description = .init(annotation.subtitle.flatMap { $0 } ?? L10n.SimpleAnnotationDetail.Description.default)
        closeButtonVisible = .init(true)

        avatar = .init(nil)

        primaryButtonTitle = .init("")
        primaryButtonEnabled = .init(false)
        primaryButtonVisible = .init(false)

        secondaryButtonTitle = .init("")
        secondaryButtonEnabled = .init(false)
        secondaryButtonVisible = .init(false)
    }

    func update() {
        description.wrappedValue = addressLocalizer.generic(coordinate: annotation.coordinate, relativeTo: nil)
    }

    func close() {
        delegate?.remove(annotation: annotation)
        delegate?.hideDetails(animated: true)
    }

    func hide() {
        delegate?.hideDetails(animated: true)
    }

    func primaryAction() {
    }

    func secondaryAction() {
    }
}

class LocationAnnotationDetailViewModel: AnnotationDetailViewModel {

    var annotation: LocationAnnotation
    var team: Team

    weak var delegate: TeamMapViewController?

    let teamManager: TeamManagerType
    let coordinator: MainFlow
    let geocoder: GeocoderType
    let addressLocalizer: AddressLocalizerType
    let tracker: TrackerType

    var title: MutableObservable<String>
    var description: MutableObservable<String>
    var closeButtonVisible: MutableObservable<Bool>

    var avatar: MutableObservable<UIImage?>

    var primaryButtonTitle: MutableObservable<String>
    var primaryButtonEnabled: MutableObservable<Bool>
    var primaryButtonVisible: MutableObservable<Bool>

    var secondaryButtonTitle: MutableObservable<String>
    var secondaryButtonEnabled: MutableObservable<Bool>
    var secondaryButtonVisible: MutableObservable<Bool>

    init(annotation: LocationAnnotation, team: Team, teamManager: TeamManagerType, coordinator: MainFlow, geocoder: GeocoderType, addressLocalizer: AddressLocalizerType, tracker: TrackerType) {
        self.annotation = annotation
        self.team = team
        self.teamManager = teamManager
        self.coordinator = coordinator
        self.geocoder = geocoder
        self.addressLocalizer = addressLocalizer
        self.tracker = tracker

        title = .init(L10n.LocationAnnotationDetail.title)
        description = .init("")
        closeButtonVisible = .init(true)

        avatar = .init(nil)

        primaryButtonTitle = .init(L10n.LocationAnnotationDetail.createMeetingPoint)
        primaryButtonEnabled = .init(true)
        primaryButtonVisible = .init(true)

        secondaryButtonTitle = .init("")
        secondaryButtonEnabled = .init(false)
        secondaryButtonVisible = .init(false)
    }

    func update() {
        firstly {
            geocoder.reverseGeocode(location: annotation.location)
        }.done { [weak self] placemark in
            guard let self = self else { return }
            self.annotation.placemark = placemark
        }.ensure {
            self.updateDescription()
        }.cauterize()
    }
    
    func updateDescription() {
        description.wrappedValue = addressLocalizer.full(annotation: annotation)
    }

    func close() {
        delegate?.remove(annotation: annotation)
        delegate?.hideDetails(animated: true)
    }

    func hide() {
        delegate?.hideDetails(animated: true)
    }

    func primaryAction() {
        set(meetingPoint: annotation.coordinate, for: team)
    }

    func set(meetingPoint: CLLocationCoordinate2D, for team: Team) {
        firstly { () -> Promise<Void> in
            primaryButtonEnabled.wrappedValue = false
            secondaryButtonEnabled.wrappedValue = false
            return self.teamManager.set(meetingPoint: meetingPoint, in: team)
        }.done { _ in
            self.close()
            self.tracker.log(action: .removeMember, category: .app, detail: "SUCCESS")
        }.catch(policy: .allErrors) { error in
            self.tracker.log(action: .removeMember, category: .app, detail: error.isCancelled ? "CANCELLED" : "ERROR")
            guard !error.isCancelled else { return }
            self.coordinator.show(error: error)
        }.finally {
            self.primaryButtonEnabled.wrappedValue = true
            self.secondaryButtonEnabled.wrappedValue = true
            self.update()
        }
    }

    func secondaryAction() {
        // nop
    }
}

class DemoUserAnnotationDetailViewModel: AnnotationDetailViewModel {
    
    let demoManager: DemoManagerType
    let geocoder: GeocoderType
    let addressLocalizer: AddressLocalizerType
    
    var title: MutableObservable<String>
    var description: MutableObservable<String>
    var closeButtonVisible: MutableObservable<Bool>
    var avatar: MutableObservable<UIImage?>
    var primaryButtonTitle: MutableObservable<String>
    var primaryButtonEnabled: MutableObservable<Bool>
    var primaryButtonVisible: MutableObservable<Bool>
    var secondaryButtonTitle: MutableObservable<String>
    var secondaryButtonEnabled: MutableObservable<Bool>
    var secondaryButtonVisible: MutableObservable<Bool>
    
    weak var delegate: TeamMapViewController?
    
    let annotation: DemoUserAnnotation
    var cachedAddress: CLPlacemark?
    
    init(demoManager: DemoManagerType, geocoder: GeocoderType, addressLocalizer: AddressLocalizerType, annotation: DemoUserAnnotation) {
        self.demoManager = demoManager
        self.geocoder = geocoder
        self.addressLocalizer = addressLocalizer
        
        self.annotation = annotation

        title = .init(annotation.title ?? L10n.UserAnnotationDetail.Title.default)
        description = .init(annotation.subtitle ?? L10n.UserAnnotationDetail.Description.default)
        closeButtonVisible = .init(true)

        avatar = .init(demoManager.avatar(demoUser: annotation.user))

        primaryButtonTitle = .init("")
        primaryButtonEnabled = .init(false)
        primaryButtonVisible = .init(false)

        secondaryButtonTitle = .init("")
        secondaryButtonEnabled = .init(false)
        secondaryButtonVisible = .init(false)
    }
    
    func update() {
        firstly {
            geocoder.reverseGeocode(location: annotation.location)
        }.done { [weak self] placemark in
            guard let self = self else { return }
            self.annotation.placemark = placemark
        }.ensure {
            self.updateDescription()
        }.cauterize()
    }
    
    func updateDescription() {
        let address = addressLocalizer.short(annotation: annotation)
        let timeAgo = annotation.location.timestamp.timeAgo(minSeconds: 10)
        description.wrappedValue = "\(address) · \(timeAgo)"
    }
    
    func close() {
        delegate?.hideDetails(animated: true)
    }

    func hide() {
        delegate?.hideDetails(animated: true)
    }
    
    func primaryAction() {
        
    }
    
    func secondaryAction() {
        
    }
}

class DemoMeetingPointDetailViewModel: AnnotationDetailViewModel {

    let demoManager: DemoManagerType
    let geocoder: GeocoderType
    let addressLocalizer: AddressLocalizerType
    let annotation: MeetingPointAnnotation
    
    weak var delegate: TeamMapViewController?

    let title: MutableObservable<String>
    let description: MutableObservable<String>
    let closeButtonVisible: MutableObservable<Bool>

    let avatar: MutableObservable<UIImage?>

    let primaryButtonTitle: MutableObservable<String>
    let primaryButtonEnabled: MutableObservable<Bool>
    let primaryButtonVisible: MutableObservable<Bool>

    let secondaryButtonTitle: MutableObservable<String>
    let secondaryButtonEnabled: MutableObservable<Bool>
    let secondaryButtonVisible: MutableObservable<Bool>

    init(demoManager: DemoManagerType, geocoder: GeocoderType, addressLocalizer: AddressLocalizerType, annotation: MeetingPointAnnotation) {
        self.demoManager = demoManager
        self.geocoder = geocoder
        self.addressLocalizer = addressLocalizer
        self.annotation = annotation
        
        title = .init(L10n.MeetingPointDetail.title)
        description = .init(L10n.MeetingPointDetail.Description.default)
        closeButtonVisible = .init(true)

        avatar = .init(nil)

        primaryButtonTitle = .init("")
        primaryButtonEnabled = .init(false)
        primaryButtonVisible = .init(false)

        secondaryButtonTitle = .init("")
        secondaryButtonEnabled = .init(false)
        secondaryButtonVisible = .init(false)
    }

    func update() {
        guard demoManager.demoTeam.wrappedValue.demoUsersSharingLocation else {
            close()
            return
        }
        
        firstly {
            geocoder.reverseGeocode(location: annotation.location)
        }.done { [weak self] placemark in
            guard let self = self else { return }
            self.annotation.placemark = placemark
        }.ensure {
            self.updateDescription()
        }.cauterize()
        
        primaryButtonTitle.wrappedValue = L10n.MeetingPointDetail.isMeetingPoint
        primaryButtonEnabled.wrappedValue = false
        primaryButtonVisible.wrappedValue = true

        secondaryButtonTitle.wrappedValue = L10n.MeetingPointDetail.delete
        secondaryButtonEnabled.wrappedValue = true
        secondaryButtonVisible.wrappedValue = true
    }

    func updateDescription() {
        description.wrappedValue = addressLocalizer.short(annotation: annotation)
    }

    func primaryAction() {
        // nop
    }

    func secondaryAction() {
        guard demoManager.demoTeam.wrappedValue.demoUsersSharingLocation else {
            logger.warning("Secondary button of annotation detail was pressed without demo users sharing their location")
            return
        }

        demoManager.didDeleteMeetingPoint()
    }

    func close() {
        delegate?.hideDetails(animated: true)
    }

    func hide() {
        delegate?.hideDetails(animated: true)
    }
}

class UserAnnotationDetailViewModel: AnnotationDetailViewModel {

    let annotation: UserAnnotation

    let avatarSupplier: AvatarSupplierType
    let geocoder: GeocoderType
    let addressLocalizer: AddressLocalizerType

    weak var delegate: TeamMapViewController?

    let title: MutableObservable<String>
    let description: MutableObservable<String>
    let closeButtonVisible: MutableObservable<Bool>

    let avatar: MutableObservable<UIImage?>

    let primaryButtonTitle: MutableObservable<String>
    let primaryButtonEnabled: MutableObservable<Bool>
    let primaryButtonVisible: MutableObservable<Bool>

    let secondaryButtonTitle: MutableObservable<String>
    let secondaryButtonEnabled: MutableObservable<Bool>
    let secondaryButtonVisible: MutableObservable<Bool>
    
    let formatter: MeasurementFormatter

    init(annotation: UserAnnotation, avatarSupplier: AvatarSupplierType, geocoder: GeocoderType, addressLocalizer: AddressLocalizerType) {
        self.annotation = annotation

        self.avatarSupplier = avatarSupplier
        self.geocoder = geocoder
        self.addressLocalizer = addressLocalizer
        
        self.formatter = MeasurementFormatter()
        formatter.numberFormatter.maximumFractionDigits = 0

        title = .init(annotation.title ?? L10n.UserAnnotationDetail.Title.default)
        description = .init(annotation.subtitle ?? L10n.UserAnnotationDetail.Description.default)
        closeButtonVisible = .init(true)

        avatar = .init(avatarSupplier.avatar(user: annotation.user, size: CGSize(width: 50, height: 50), rounded: false))

        primaryButtonTitle = .init(L10n.UserAnnotationDetail.follow)
        primaryButtonEnabled = .init(true)
        primaryButtonVisible = .init(true)

        secondaryButtonTitle = .init("")
        secondaryButtonEnabled = .init(false)
        secondaryButtonVisible = .init(false)
    }

    func update() {
        firstly {
            geocoder.reverseGeocode(location: annotation.location)
        }.done { [weak self] placemark in
            guard let self = self else { return }
            self.annotation.placemark = placemark
        }.ensure {
            self.updateDescription()
        }.cauterize()
    }
    
    func updateDescription() {
        let address = addressLocalizer.short(annotation: annotation)
        let timeAgo = annotation.alwaysUpToDate ? L10n.TimeAgo.Second.last : annotation.location.timestamp.timeAgo(minSeconds: 10)
        let speedMeasurement = Measurement(value: annotation.location.speed > 0 ? annotation.location.speed : 0, unit: UnitSpeed.metersPerSecond)
        let speedDescription = formatter.string(from: speedMeasurement)
        description.wrappedValue = "\(address)\n\(speedDescription) · \(timeAgo)"
    }

    func close() {
        delegate?.hideDetails(animated: true)
    }

    func hide() {
        delegate?.hideDetails(animated: true)
    }

    func primaryAction() {
        if annotation.user is SignedInUser {
            delegate?.setUserTrackingMode(mode: .follow)
        } else {
            delegate?.follow(annotation: annotation)
        }
    }

    func secondaryAction() {
    }
}

class MeetingPointDetailViewModel: AnnotationDetailViewModel {

    let annotation: MeetingPointAnnotation
    let team: Team
    let geocoder: GeocoderType
    let addressLocalizer: AddressLocalizerType

    weak var delegate: TeamMapViewController?

    let teamManager: TeamManagerType
    let coordinator: MainFlow
    let dateFormatter: DateFormatter

    let title: MutableObservable<String>
    let description: MutableObservable<String>
    let closeButtonVisible: MutableObservable<Bool>

    let avatar: MutableObservable<UIImage?>

    let primaryButtonTitle: MutableObservable<String>
    let primaryButtonEnabled: MutableObservable<Bool>
    let primaryButtonVisible: MutableObservable<Bool>

    let secondaryButtonTitle: MutableObservable<String>
    let secondaryButtonEnabled: MutableObservable<Bool>
    let secondaryButtonVisible: MutableObservable<Bool>

    init(annotation: MeetingPointAnnotation, team: Team, teamManager: TeamManagerType, coordinator: MainFlow, geocoder: GeocoderType, addressLocalizer: AddressLocalizerType) {
        self.annotation = annotation
        self.team = team
        self.teamManager = teamManager
        self.coordinator = coordinator
        self.geocoder = geocoder
        self.addressLocalizer = addressLocalizer

        dateFormatter = DateFormatter()
        dateFormatter.timeStyle = .long
        dateFormatter.dateStyle = .short

        title = .init(L10n.MeetingPointDetail.title)
        description = .init(L10n.MeetingPointDetail.Description.default)
        closeButtonVisible = .init(true)

        avatar = .init(nil)

        primaryButtonTitle = .init("")
        primaryButtonEnabled = .init(false)
        primaryButtonVisible = .init(false)

        secondaryButtonTitle = .init("")
        secondaryButtonEnabled = .init(false)
        secondaryButtonVisible = .init(false)
    }

    func update() {
        firstly {
            geocoder.reverseGeocode(location: annotation.location)
        }.done { [weak self] placemark in
            guard let self = self else { return }
            self.annotation.placemark = placemark
        }.ensure {
            self.updateDescription()
        }.cauterize()

        primaryButtonTitle.wrappedValue = L10n.MeetingPointDetail.isMeetingPoint
        primaryButtonEnabled.wrappedValue = false
        primaryButtonVisible.wrappedValue = true

        secondaryButtonTitle.wrappedValue = L10n.MeetingPointDetail.delete
        secondaryButtonEnabled.wrappedValue = true
        secondaryButtonVisible.wrappedValue = true
    }
    
    func updateDescription() {
        let address = addressLocalizer.short(annotation: annotation)
        let timeAgo = L10n.TimeAgo.short(annotation.location.timestamp.shortTimeAgo())
        description.wrappedValue = "\(address) · \(timeAgo)"
    }
    
    func primaryAction() {
        // nop
    }

    func secondaryAction() {
        firstly { () -> Promise<Void> in
            secondaryButtonEnabled.wrappedValue = false
            return self.teamManager.set(meetingPoint: nil, in: team)
        }.done {
            self.close()
        }.ensure {
            self.secondaryButtonEnabled.wrappedValue = true
            self.update()
        }.catch { error in
            self.coordinator.show(error: error)
        }
    }

    func close() {
        delegate?.hideDetails(animated: true)
    }

    func hide() {
        delegate?.hideDetails(animated: true)
    }
}
