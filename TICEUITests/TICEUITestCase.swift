//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import XCTest
import TICEAPIModels
import ConvAPI

func Localized(_ key: String) -> String {
    return LocalizedString(key, bundle: Bundle(for: TICEUITestCase.self))
}

class TICEUITestCase: XCTestCase {
    var cncAPI: CnCAPI!
    
    lazy var infoPlist: NSDictionary = {
        let url = Bundle(for: TICEUITestCase.self).url(forResource: "Info", withExtension: "plist")!
        return NSDictionary(contentsOf: url)!
    }()
    
    lazy var cncBaseURL: URL = {
        let address = infoPlist["CNC_SERVER_ADDRESS"] as! String
        return URL(string: address)!
    }()
    
    lazy var buildNumber: Int = {
        let bundleVersion = infoPlist["CFBundleVersion"] as! String
        return Int(bundleVersion)!
    }()
    
    override func setUp() {
        URLSession.shared.delegateQueue.maxConcurrentOperationCount = -1
        let convAPI = ConvAPI(requester: URLSession.shared)
        let backend = Backend(api: convAPI, baseURL: cncBaseURL)
        cncAPI = CnC(backend: backend)
        
        continueAfterFailure = false
        
        let serverAddress = infoPlist["SERVER_ADDRESS"] as! String
        let wsServerAddress = infoPlist["WS_SERVER_ADDRESS"] as! String
        
        let app = XCUIApplication()
        app.launchArguments = ["UITESTING"]
        app.launchArguments.append(contentsOf: ["-SERVER_ADDRESS", serverAddress])
        app.launchArguments.append(contentsOf: ["-WS_SERVER_ADDRESS", wsServerAddress])
        app.launch()
    }
    
    override func record(_ issue: XCTIssue) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        
        let filteredName = name.filter { !"[]-+".contains($0) }
        let noSpaceName = filteredName.replacingOccurrences(of: " ", with: "-")
        attachment.name = "FAILURE_\(noSpaceName).png"
        
        var issue = issue
        issue.add(attachment)
        super.record(issue)
    }
}

func openURLViaSpotlight(_ urlString: String, returnToApp app: XCUIApplication?, timeout: TimeInterval = 5.0) {
    XCUIDevice.shared.press(.home)
    XCUIApplication(bundleIdentifier: "com.apple.springboard").waitAndSwipeDown(timeout: timeout)
    let spotlight = XCUIApplication(bundleIdentifier: "com.apple.Spotlight")
    spotlight.textFields["SpotlightSearchField"].waitAndTypeText(urlString, timeout: timeout)
    spotlight.buttons["Go"].waitAndTap(timeout: timeout)
    
    if let app = app {
        XCTAssert(app.wait(for: .runningForeground, timeout: timeout))
    }
}
