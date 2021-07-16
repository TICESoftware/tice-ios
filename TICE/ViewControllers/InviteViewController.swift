//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import Observable
import Swinject

class DoneActivity: UIActivity {

    var handler: (() -> Void)?

    override var activityType: UIActivity.ActivityType? { return .init("done") }
    override var activityTitle: String? { return L10n.Invite.done }
    override var activityImage: UIImage? { return UIImage(named: "closeButton") }

    override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        return true
    }

    override func perform() {
        handler?()
    }
}

class InviteViewController: UIViewController {

    var viewModel: InviteViewModel! {
        didSet {
            viewModel.delegate = self
        }
    }
    
    var disposal = Disposal()

    @IBOutlet weak var previewLabel: UILabel!
    @IBOutlet weak var doneButton: UIBarButtonItem!

    @IBAction func doneButtonTapped(_ sender: UIBarButtonItem) {
        viewModel.done()
    }

    @IBAction func shareButtonTapped(_ sender: UIBarButtonItem) {
        viewModel.shareButtonTapped()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        viewModel.invitationText.observe { value, _ in
            self.previewLabel.text = value
        }.add(to: &disposal)
        
        viewModel.viewDidLoad()
    }

    func showShareScreen(invitation: TeamShareInvitation,
                         completionWithItemsHandler: @escaping UIActivityViewController.CompletionWithItemsHandler) {
        let doneActivity = DoneActivity()
        doneActivity.handler = { [weak self] in
            self?.viewModel.done()
        }

        let activityViewController = UIActivityViewController(activityItems: [invitation], applicationActivities: nil)
        activityViewController.completionWithItemsHandler = completionWithItemsHandler
        
        present(activityViewController, animated: true, completion: nil)
    }
}

class InviteViewModel {
    
    let nameSupplier: NameSupplierType
    let tracker: TrackerType
    let resolver: Swinject.Resolver
    
    unowned var coordinator: InviteFlow
    weak var delegate: InviteViewController?
    
    let team: Team
    let invitationText: MutableObservable<String>
    
    init(nameSupplier: NameSupplierType, tracker: TrackerType, resolver: Swinject.Resolver, coordinator: InviteFlow, team: Team) {
        self.nameSupplier = nameSupplier
        self.tracker = tracker
        self.resolver = resolver
        self.coordinator = coordinator
        self.team = team
        self.invitationText = .init(L10n.Invite.invitation(nameSupplier.name(team: team), "\(team.shareURL)"))
    }
    
    func done() {
        coordinator.invitingDone(team: team)
    }
    
    func shareButtonTapped() {
        showShareScreen()
    }
    
    func viewDidLoad() {
        showShareScreen()
    }
    
    func showShareScreen() {
        let invitation = resolver.resolve(TeamShareInvitation.self, argument: team)!
        let completion: UIActivityViewController.CompletionWithItemsHandler = { [weak self] activityType, completed, _, activityError in
            let cancelled = activityType == nil && activityError == nil
            self?.tracker.log(action: .invite, category: .app, detail: cancelled ? "CANCELLED" : activityType?.rawValue)
            if activityType != nil && completed || activityType == nil && !completed {
                (UIApplication.shared.delegate as? AppDelegate)?.setupDesign()
            }
        }
        (UIApplication.shared.delegate as? AppDelegate)?.resetDesign()
        delegate?.showShareScreen(invitation: invitation, completionWithItemsHandler: completion)
    }
}
