//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import Swinject
import SwinjectStoryboard
import UIKit

protocol InviteFlow: Coordinator {
    func invitingDone(team: Team)
}

protocol CreateTeamFlow: InviteFlow {
    func start() -> UIViewController
    func cancel()
    func creatingDone(team: Team)
    func fail(error: Error?)
    
    var source: String { get }
}

class CreateTeamCoordinator: NSObject, Coordinator {

    weak var parent: MainFlow?
    var source: String

    let window: UIWindow
    let storyboard: UIStoryboard
    let resolver: Swinject.Resolver
    let tracker: TrackerType
    let navigationController = UINavigationController()

    var children: [Coordinator] = []

    init(tracker: TrackerType, parent: MainFlow, source: String) {
        self.parent = parent
        self.window = parent.window
        self.storyboard = parent.storyboard
        self.resolver = parent.resolver
        self.tracker = tracker
        self.source = source
    }
}

extension CreateTeamCoordinator: CreateTeamFlow {

    func start() -> UIViewController {
        let createTeamViewController = storyboard.instantiateViewController(CreateTeamViewController.self)
        createTeamViewController.viewModel = resolver.resolve(CreateTeamViewModel.self, argument: self as CreateTeamFlow)
        navigationController.setViewControllers([createTeamViewController], animated: false)
        navigationController.presentationController?.delegate = self
        return navigationController
    }

    func cancel() {
        guard let parent = parent else {
            logger.debug("No parent for flow \(self)")
            return
        }

        parent.cancel(createTeamFlow: self, didDismiss: false)
    }

    func creatingDone(team: Team) {
        let inviteViewController = storyboard.instantiateViewController(InviteViewController.self)
        inviteViewController.viewModel = resolver.resolve(InviteViewModel.self, arguments: self as InviteFlow, team)
        navigationController.setViewControllers([inviteViewController], animated: true)
    }

    func invitingDone(team: Team) {
        guard let parent = parent else {
            logger.debug("No parent for flow \(self)")
            return
        }

        parent.finish(createTeamFlow: self, team: team)
    }

    func fail(error: Error?) {
        show(error: error)
    }
}

extension CreateTeamCoordinator: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard let parent = parent else {
            logger.debug("No parent for flow \(self)")
            return
        }
        
        parent.cancel(createTeamFlow: self, didDismiss: true)
    }
}
