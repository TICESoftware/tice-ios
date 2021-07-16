//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import Swinject

extension DependencyRegistrator {
    
    func extensionContainer() -> Container {
        return Container { container in
            setupCommonContainer(container: container)
            setupExtensionContainer(container: container, config: config)
        }
    }
    
    private func setupExtensionContainer(container: Container, config: Config) {
        container.autoregister(SignedInUserManagerType.self, initializer: ExtensionSignedInUserManager.init).inObjectScope(.container)
        container.autoregister(LocationManagerType.self, initializer: PassiveLocationManager.init).inObjectScope(.container)
        container.autoregister(TrackerType.self, initializer: MockTracker.init).inObjectScope(.container)
    }
}
