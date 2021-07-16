//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import Pulley
import CoreLocation
import MapKit
import PromiseKit
import Observable
import Contacts

class ClusterUserViewCell: UICollectionViewCell {
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var imageView: UIImageView!
}

class ClusterAnnotationDetailViewController: UIViewController, PulleyDrawerViewControllerDelegate, UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    var viewModel: ClusterAnnotationDetailViewModel!
    var disposal: Disposal = Disposal()
    var timer: Timer?

    @IBOutlet weak var containerView: UIView!
    
    @IBOutlet weak var avatarView: UIImageView!

    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var descriptionLabel: UILabel!
    @IBOutlet weak var closeButton: UIButton!
    
    @IBOutlet weak var collectionView: UICollectionView!

    override func viewDidLoad() {
        super.viewDidLoad()

        viewModel.title.observe(.main) { [weak self] value, _ in self?.titleLabel.text = value }.add(to: &disposal)
        viewModel.description.observe(.main) { [weak self] value, _ in self?.descriptionLabel.text = value }.add(to: &disposal)
        viewModel.closeButtonVisible.observe(.main) { [weak self] value, _ in self?.closeButton.isHidden = !value }.add(to: &disposal)

        viewModel.avatar.observe(.main) { [weak self] value, _ in
            self?.avatarView.isHidden = value == nil
            self?.avatarView.image = value
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
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return viewModel.numberOfUsers
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        // swiftlint:disable:next force_cast
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ClusterUserViewCell", for: indexPath) as! ClusterUserViewCell
        cell.imageView.image = viewModel.avatar(index: indexPath.item)
        cell.titleLabel.text = viewModel.name(index: indexPath.item)
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: 80, height: 80)
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        viewModel.didSelect(index: indexPath.item)
    }
}

class ClusterAnnotationDetailViewModel: AnnotationDetailViewModel {
    var annotation: MKClusterAnnotation
    let avatarSupplier: AvatarSupplierType
    let nameSupplier: NameSupplierType
    
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

    init(annotation: MKClusterAnnotation, avatarSupplier: AvatarSupplierType, nameSupplier: NameSupplierType) {
        self.annotation = annotation
        self.avatarSupplier = avatarSupplier
        self.nameSupplier = nameSupplier
        
        title = .init(L10n.ClusterAnnotationDetail.title)

        description = .init(L10n.ClusterAnnotationDetail.description("\(annotation.memberAnnotations.count)"))
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
    
    var numberOfUsers: Int {
        return annotation.memberAnnotations.count
    }
    
    private func user(index: Int) -> User {
        // swiftlint:disable:next force_cast
        return (annotation.memberAnnotations[index] as! UserAnnotation).user
    }
    
    func avatar(index: Int) -> UIImage {
        avatarSupplier.avatar(user: user(index: index), size: CGSize(width: 56, height: 56), rounded: false)
    }
    
    func name(index: Int) -> String {
        nameSupplier.name(user: user(index: index))
    }
    
    func didSelect(index: Int) {
        delegate?.showDetails(for: annotation.memberAnnotations[index], animated: true)
    }
}
