//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import Version

extension Bundle {
    
    /// This function returns the app bundle ID (e.g. app.tice.TICE.development) of the
    /// current environment (e.g. Development) and is safe to call from extensions.
    var appBundleId: String {
        return "app.tice.TICE.\(environment)"
    }
    
    var environment: String {
        #if DEBUG
        return "development"
        #elseif TESTING
        return "testing"
        #elseif PREVIEW
        return "preview"
        #else
        return "production"
        #endif
    }
    
    var appVersion: Version {
        // swiftlint:disable:next force_cast
        let versionString = Bundle.main.infoDictionary!["APP_VERSION"] as! String
        // swiftlint:disable:next force_try
        var version = try! Version(versionString)
        version.prerelease = "\(buildNumber)"
        return version
    }

    var verboseVersionString: String {
        return "\(appVersion) @ \(environment)"
    }
}
