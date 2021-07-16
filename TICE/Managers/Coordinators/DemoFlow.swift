//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import Swinject
import SwinjectStoryboard

protocol DemoFlow: Coordinator {
    func start() -> UIViewController
    
    func showChat()
    func leaveChat()
    
    func showTeamSettingsScreen()
    func didDeleteTeam()
}

class DemoCoordinator: NSObject, Coordinator {

    weak var parent: MainFlow?

    let window: UIWindow
    let storyboard: UIStoryboard
    let resolver: Swinject.Resolver

    var children: [Coordinator] = []
    
    let navigationController: UINavigationController

    init(parent: MainFlow, navigationController: UINavigationController) {
        self.parent = parent
        self.window = parent.window
        self.storyboard = parent.storyboard
        self.resolver = parent.resolver
        self.navigationController = navigationController
    }
}

extension DemoCoordinator: DemoFlow {

    func start() -> UIViewController {
        navigationController.delegate = self
        
        let teamMapViewController = storyboard.instantiateViewController(TeamMapViewController.self)
        teamMapViewController.viewModel = resolver.resolve(DemoTeamMapViewModel.self, argument: self as DemoFlow)
        teamMapViewController.chatViewModel = resolver.resolve(DemoTeamMapChatViewModel.self, argument: self as DemoFlow)
        
        let teamViewController = storyboard.instantiateViewController(TeamViewController.self)
        teamViewController.viewModel = resolver.resolve(DemoTeamViewModel.self, argument: self as DemoFlow)
        teamViewController.groupMapViewController = teamMapViewController
        
        return teamViewController
    }
    
    func showTeamSettingsScreen() {
        let teamSettingsViewController = storyboard.instantiateViewController(TeamSettingsViewController.self)
        teamSettingsViewController.viewModel = resolver.resolve(DemoTeamSettingsViewModel.self, argument: self as DemoFlow)
        navigationController.pushViewController(teamSettingsViewController, animated: true)
    }
    
    func showChat() {
        let chatViewModel = resolver.resolve(DemoChatViewModel.self, argument: self as DemoFlow)

        let chatViewController = storyboard.instantiateViewController(ChatViewController.self)
        chatViewController.viewModel = chatViewModel
        
        navigationController.present(UINavigationController(rootViewController: chatViewController), animated: true, completion: nil)
    }
    
    func leaveChat() {
        navigationController.dismiss(animated: true, completion: nil)
    }
    
    func didDeleteTeam() {
        navigationController.popToRootViewController(animated: true)
    }
    
    func finish() {
        parent?.finish(demoFlow: self)
    }
}

extension DemoCoordinator: UINavigationControllerDelegate {
    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        if navigationController.viewControllers.count <= 1 {
            finish()
        }
    }
}
