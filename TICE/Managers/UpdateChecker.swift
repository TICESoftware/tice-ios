//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import PromiseKit
import TICEAPIModels
import ConvAPI

struct MinVersion: Codable {
    let iOS: Int
}

struct ServerInformationResponse: Codable {
    let deployedAt: Date?
    let deployedCommit: String?
    let env: String
    let minVersion: MinVersion
}

enum UpdateCheckerError: LocalizedError {
    case outdated(minVersion: Int)

    var errorDescription: String? {
        switch self {
        case .outdated(let minVersion):
            return L10n.Update.Error.outdated("\(minVersion)")
        }
    }
}

protocol UpdateCheckerType {
    func check() -> Promise<Void>
}

class UpdateChecker: UpdateCheckerType {

    let backendURL: URL
    let api: API
    let currentVersion: Int

    init(backendURL: URL, api: API, currentVersion: Int) {
        self.backendURL = backendURL
        self.api = api
        self.currentVersion = currentVersion
    }

    func check() -> Promise<Void> {
        return firstly { () -> Promise<ServerInformationResponse> in
            api.request(method: .GET, baseURL: backendURL, resource: "/", error: APIError.self)
        }.done { information in
            guard self.currentVersion >= information.minVersion.iOS else {
                throw UpdateCheckerError.outdated(minVersion: information.minVersion.iOS)
            }
        }
    }
}
