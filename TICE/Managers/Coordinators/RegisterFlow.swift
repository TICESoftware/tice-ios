//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import Swinject
import SwinjectStoryboard

protocol RegisterFlow: Coordinator {
    func start()
    func finish()
    func fail(error: Error)
}

class DebugRegisterCoordinator: Coordinator {

    weak var parent: AppFlow?

    let window: UIWindow
    let storyboard: UIStoryboard
    let resolver: Swinject.Resolver

    var children: [Coordinator] = []

    init(parent: AppFlow) {
        self.parent = parent
        self.window = parent.window
        self.storyboard = parent.storyboard
        self.resolver = parent.resolver
    }
}

extension DebugRegisterCoordinator: RegisterFlow {

    func start() {
        let registerViewController = storyboard.instantiateViewController(DebugRegisterViewController.self)
        let registerViewModel = resolver.resolve(RegisterViewModelType.self, argument: self as RegisterFlow)!
        registerViewController.viewModel = registerViewModel
        registerViewController.viewModel.delegate = registerViewController
        window.rootViewController = registerViewController
    }

    func finish() {
        guard let parent = parent else {
            logger.debug("No parent for flow \(self)")
            return
        }
        
        parent.finish(registerFlow: self)
    }

    func fail(error: Error) {
        show(error: error)
    }
}

class RegisterCoordinator: Coordinator {

    weak var parent: AppFlow?

    let window: UIWindow
    let storyboard: UIStoryboard
    let resolver: Swinject.Resolver

    var children: [Coordinator] = []

    init(parent: AppFlow) {
        self.parent = parent
        self.window = parent.window
        self.storyboard = parent.storyboard
        self.resolver = parent.resolver
    }
}

extension RegisterCoordinator: RegisterFlow {

    func start() {
        let registerViewController = storyboard.instantiateViewController(RegisterViewController.self)
        let registerViewModel = resolver.resolve(RegisterViewModelType.self, argument: self as RegisterFlow)!
        registerViewController.viewModel = registerViewModel
        registerViewController.viewModel.delegate = registerViewController
        window.rootViewController = registerViewController
    }

    func finish() {
        guard let parent = parent else {
            logger.debug("No parent for flow \(self)")
            return
        }

        parent.finish(registerFlow: self)
    }

    func fail(error: Error) {
        show(error: error)
    }
}
