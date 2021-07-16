//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import XCTest
import Version

@testable import TICE

class VersionStorageManagerTests: XCTestCase {

    func testStoringVersion() {
        let userDefaults = UserDefaults(suiteName: #function)!
        let firstVersionStorageManager = VersionStorageManager(userDefaults: userDefaults)
        
        let version = Version("1.2.3")
        firstVersionStorageManager.store(version: version)
        
        let secondVersionStorageManager = VersionStorageManager(userDefaults: userDefaults)
        XCTAssertEqual(secondVersionStorageManager.loadVersion(), version)
    }
    
    func testLoadingFromNothing() {
        let userDefaults = UserDefaults(suiteName: #function)!
        let versionStorageManager = VersionStorageManager(userDefaults: userDefaults)
        
        XCTAssertNil(versionStorageManager.loadVersion())
    }
    
}
