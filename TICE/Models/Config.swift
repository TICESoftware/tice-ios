//
//  Copyright © 2018 TICE Software UG (haftungsbeschränkt). All rights reserved.
//

import Foundation
import UIKit
import Swinject
import SwinjectStoryboard
import Version

struct Config {
    
    static let logIdentifier = "TICELog"
    static let logHistoryLimit: TimeInterval = 24 * 60 * 60
    
    struct TrackerParams {
        var product: String
        var baseURL: URL
        var path: String
        var timeout: TimeInterval
        var maxBatchSize: Int
        var secret: String
    }
    
    struct CryptoParams {
        let maxSkip: Int
        let maxCache: Int
        let info: String
        let maxOneTimePrekeyCount: Int
    }

    var backendBaseURL: URL
    var backendWebSocketURL: URL

    var pushReceiverTimeout: TimeInterval
    var registerShowCancelTimeout: TimeInterval
    var registerRoundTripTimeout: TimeInterval
    var userCacheTimeout: TimeInterval
    var envelopeCacheTime: TimeInterval
    var requestTimeout: TimeInterval
    var webSocketReconnectTime: TimeInterval

    var locationResendTimeout: TimeInterval
    var meetupReloadTimeout: TimeInterval

    var appGroupName: String

    var databaseURL: URL
    var databaseKeyLength: Int
    
    let cryptoParams: CryptoParams
    
    var certificateValidityTimeRenewalThreshold: TimeInterval

    var collapsingConversationIdentifier: UUID
    var nonCollapsingConversationIdentifier: UUID
    
    var resendResetTimeout: TimeInterval
    var locationMaxAge: TimeInterval
    var checkOutdatedLocationSharingStateInterval: TimeInterval
    
    var groupNameLimit: Int
    var pseudonymNamesFileURL: URL

    var valetId: String

    var version: Version
    var buildNumber: Int
    var minPreviousVersion: Version
    var platform: String

    let trackerParams: TrackerParams
    
    let chatLoadLimit: Int
    
    let logHistoryOffsetUserFeedback: TimeInterval
    let logHistoryOffsetMigrationFailure: TimeInterval

    static var infoPlist: Config {
        // swiftlint:disable force_cast
        let url = Bundle.main.url(forResource: "Info", withExtension: "plist")!
        let dictionary = NSDictionary(contentsOf: url)!

        let baseURL: URL
        let webSocketBaseURL: URL

        if ProcessInfo.processInfo.arguments.contains("USE_PLAIN") {
            baseURL = URL(string: dictionary["PLAIN_SERVER_ADDRESS"] as! String)!
            webSocketBaseURL = URL(string: dictionary["WS_PLAIN_SERVER_ADDRESS"] as! String)!
        } else if ProcessInfo.processInfo.arguments.contains("USE_LOCAL_SERVER") {
            baseURL = URL(string: "http://localhost:1500")!
            webSocketBaseURL = URL(string: "ws://localhost:1500")!
        } else {
            baseURL = URL(string: dictionary["SERVER_ADDRESS"] as! String)!
            webSocketBaseURL = URL(string: dictionary["WS_SERVER_ADDRESS"] as! String)!
        }

        let version = Bundle.main.appVersion
        let buildNumber = Bundle.main.buildNumber
        let minPreviousVersion = Version(major: 1, minor: 14, patch: 0, prerelease: "110")

        let collapsingConversationIdentifier = ConversationId(uuidString: "00000000-0000-0000-0000-000000000000")!
        let nonCollapsingConversationIdentifier = ConversationId(uuidString: "00000000-0000-0000-0000-000000000001")!

        let appBundleId = Bundle.main.appBundleId
        let appGroupName = "group." + appBundleId
        let valetId = appBundleId + ".valet"

        let pseudonymNamesFileURL = URL(fileReferenceLiteralResourceName: "Pseudonyms.txt")
        
        let product = "TICE-\(Bundle.main.environment)"

        let databaseURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupName)!.appendingPathComponent("db").appendingPathExtension("sqlite")
        let databaseKeyLength = 48
        
        let trackerParams = TrackerParams(product: product,
                                          baseURL: URL(string: "https://beekeeper.tice.app")!,
                                          path: "/\(product)",
                                          timeout: 30,
                                          maxBatchSize: 10,
                                          secret: Secrets.beekeeper)
        
        let cryptoParams = CryptoParams(maxSkip: 5000, maxCache: 5010, info: "TICE", maxOneTimePrekeyCount: 100)
        
        // swiftlint:enable force_cast
        
        return Config(backendBaseURL: baseURL,
                      backendWebSocketURL: webSocketBaseURL,
                      pushReceiverTimeout: 28,
                      registerShowCancelTimeout: 10.0,
                      registerRoundTripTimeout: 90.0,
                      userCacheTimeout: 10.0 * 60,
                      envelopeCacheTime: 1800.0,
                      requestTimeout: 10.0,
                      webSocketReconnectTime: 2.0,
                      locationResendTimeout: 60.0,
                      meetupReloadTimeout: 60.0,
                      appGroupName: appGroupName,
                      databaseURL: databaseURL,
                      databaseKeyLength: databaseKeyLength,
                      cryptoParams: cryptoParams,
                      certificateValidityTimeRenewalThreshold: 60 * 60 * 24 * 30 * 6,
                      collapsingConversationIdentifier: collapsingConversationIdentifier,
                      nonCollapsingConversationIdentifier: nonCollapsingConversationIdentifier,
                      resendResetTimeout: 60.0,
                      locationMaxAge: 10 * 60.0,
                      checkOutdatedLocationSharingStateInterval: 60.0,
                      groupNameLimit: 64,
                      pseudonymNamesFileURL: pseudonymNamesFileURL,
                      valetId: valetId,
                      version: version,
                      buildNumber: buildNumber,
                      minPreviousVersion: minPreviousVersion,
                      platform: "iOS",
                      trackerParams: trackerParams,
                      chatLoadLimit: 20,
                      logHistoryOffsetUserFeedback: -24 * 60 * 60,
                      logHistoryOffsetMigrationFailure: -10 * 60)
    }

    func overwrittenFromUserDefaults() -> Config {
        var config = self

        if let userDefaultsServerAddress = UserDefaults.standard.string(forKey: "SERVER_ADDRESS") {
            config.backendBaseURL = URL(string: userDefaultsServerAddress)!
        }

        if let userDefaultsWebsocketServerAddress = UserDefaults.standard.string(forKey: "WS_SERVER_ADDRESS") {
            config.backendWebSocketURL = URL(string: userDefaultsWebsocketServerAddress)!
        }

        return config
    }
}
