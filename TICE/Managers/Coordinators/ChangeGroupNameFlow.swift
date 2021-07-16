//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import Swinject
import SwinjectStoryboard
import UIKit

protocol ChangeNameFlow: Coordinator {

    var team: Team { get }

    func start() -> UIViewController
    func cancel()
    func done()
}

class ChangeNameCoordinator: Coordinator {

    weak var parent: MainFlow?

    let window: UIWindow
    let storyboard: UIStoryboard
    let resolver: Swinject.Resolver
    let navigationController = UINavigationController()

    let team: Team
    var children: [Coordinator] = []

    init(parent: MainFlow, team: Team) {
        self.parent = parent
        self.window = parent.window
        self.storyboard = parent.storyboard
        self.resolver = parent.resolver
        self.team = team
    }
}

extension ChangeNameCoordinator: ChangeNameFlow {

    func start() -> UIViewController {
        let changeGroupNameViewController = storyboard.instantiateViewController(ChangeTeamNameViewController.self)
        changeGroupNameViewController.coordinator = self
        changeGroupNameViewController.team = team
        navigationController.setViewControllers([changeGroupNameViewController], animated: false)
        return navigationController
    }

    func cancel() {
        guard let parent = parent else {
            logger.debug("No parent for flow \(self)")
            return
        }

        parent.cancel(changeNameFlow: self)
    }

    func done() {
        guard let parent = parent else {
            logger.debug("No parent for flow \(self)")
            return
        }

        parent.finish(changeNameFlow: self)
    }
}
