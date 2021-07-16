//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import PromiseKit

protocol DeepLinkParserType {
    func deepLink(state: AppState) throws -> URL
    func state(url: URL) -> Promise<AppState>
    func team(url: URL) -> Promise<Team>
}
