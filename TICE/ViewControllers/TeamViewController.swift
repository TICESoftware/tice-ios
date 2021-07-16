//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import Chatto
import Observable

class TeamViewController: UIViewController {
    
    var viewModel: TeamViewModelType! {
        didSet {
            viewModel.delegate = self
        }
    }
    
    @IBOutlet var teamMapViewControllerContainer: UIView!
    
    var mainNavigationController: MainNavigationController {
        // swiftlint:disable:next force_cast
        navigationController as! MainNavigationController
    }
    var groupMapViewController: TeamMapViewController!
    
    var disposal = Disposal()
    
    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        
        if parent == nil {
            viewModel.didLeave()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.addChild(groupMapViewController)
        
        teamMapViewControllerContainer.addSubview(groupMapViewController.view)
        groupMapViewController.view.constrainToParent()
        groupMapViewController.didMove(toParent: self)
        
        update()
        
        viewModel.didEnter()
    }
    
    @IBAction func didTapInfo() {
        viewModel.didTapInfo()
    }
    
    func update() {
        self.title = viewModel.title
    }
}

protocol TeamViewModelType {
    var delegate: TeamViewController? { get set }
    
    var title: String { get }
    var teamAvatar: UIImage { get }
    
    func didEnter()
    func didLeave()
    func didTapInfo()
}

class TeamViewModel: TeamViewModelType {
    
    let nameSupplier: NameSupplierType
    let groupStorageManager: GroupStorageManagerType
    let avatarSupplier: AvatarSupplierType
    let notifier: Notifier
    let coordinator: MainFlow
    
    var team: Team
    
    weak var delegate: TeamViewController?
    
    private var teamObserverToken: ObserverToken?
    
    init(nameSupplier: NameSupplierType, groupStorageManager: GroupStorageManagerType, userManager: UserManagerType, avatarSupplier: AvatarSupplierType, notifier: Notifier, coordinator: MainFlow, team: Team) {
        self.nameSupplier = nameSupplier
        self.groupStorageManager = groupStorageManager
        self.avatarSupplier = avatarSupplier
        self.notifier = notifier
        self.coordinator = coordinator
        self.team = team
        
        teamObserverToken = groupStorageManager.observeTeam(groupId: team.groupId, queue: .main) { [unowned self] team, _ in
            guard let team = team else { return }
            self.team = team
            self.reloadSynchronously()
        }
    }
    
    deinit {
        teamObserverToken = nil
    }
    
    var title: String {
        return nameSupplier.name(team: team)
    }
    
    var teamAvatar: UIImage {
        return avatarSupplier.avatar(team: team, size: CGSize(width: 48, height: 48), rounded: true)
    }
    
    func didTapInfo() {
        coordinator.showTeamSettingsScreen(for: team, animated: true)
    }
    
    private func reloadSynchronously() {
        self.delegate?.update()
    }

    func reload() {
        DispatchQueue.main.async { self.reloadSynchronously() }
    }
    
    func didEnter() {
        
    }
    
    func didLeave() {
        
    }
    
    @objc
    private func handleForegroundTransition() {
        do {
            guard let team = try groupStorageManager.loadTeam(team.groupId) else { return }
            self.team = team
            reload()
        } catch {
            logger.error("Error reloading data after transition to forground: \(error)")
        }
    }
}
