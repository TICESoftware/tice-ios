//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import PromiseKit

enum AppFlowError: LocalizedError {
    case noMainFlow
    case invalidDeepLink
    case migrationFailed
    case deprecatedAppVersion

    var errorDescription: String? {
        switch self {
        case .noMainFlow: return "error_appFlow_noMainFlow"
        case .invalidDeepLink: return "error_appFlow_invalidDeepLink"
        case .migrationFailed: return L10n.Error.AppFlow.migrationFailed
        case .deprecatedAppVersion: return L10n.Error.AppFlow.deprecatedApp
        }
    }
}

protocol AppFlow: Coordinator {
    
    var deepLink: URL? { get set }
    
    func startApplication()
    func finish(registerFlow: RegisterFlow)
    func finishUpdateChecking()
    func finishHousekeeping()
    
    func handleDeepLink(to state: AppState) -> Promise<Void>
    
    func registerBackgroundTaskHandling()
}
