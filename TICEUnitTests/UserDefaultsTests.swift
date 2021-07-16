//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import XCTest

@testable import TICE

class UserDefaultsTests: XCTestCase {
    
    static func cleanUserDefaults(label: String = "UnitTest-\(#file)_\(#function)") -> UserDefaults {
        UserDefaults().removePersistentDomain(forName: label)
        return UserDefaults(suiteName: label)!
    }
    
    static func removeUserDefaults(label: String = "UnitTest-\(#file)_\(#function)") {
        UserDefaults().removePersistentDomain(forName: label)
    }
    
    func testSaveInteger() throws {
        let userDefaults = UserDefaultsTests.cleanUserDefaults()
        defer {
            UserDefaultsTests.removeUserDefaults()
        }
        
        enum Key: String {
            case test1
            case test2
        }
        
        let writtenValue = 1337
        userDefaults.set(writtenValue, forKey: Key.test1)
        let readValue: Int? = userDefaults.value(forKey: Key.test1)
        
        XCTAssertEqual(readValue, writtenValue, "Read and written values must match")
        
        let unaffectedValue: Int? = userDefaults.value(forKey: Key.test2)
        
        XCTAssertNil(unaffectedValue)
    }
    
    func testSaveData() throws {
        let userDefaults = UserDefaultsTests.cleanUserDefaults()
        defer {
            UserDefaultsTests.removeUserDefaults()
        }
        
        enum Key: String {
            case test
        }
        
        let writtenValue = "Test".data(using: .utf8)
        userDefaults.set(writtenValue, forKey: Key.test)
        let readValue: Data? = userDefaults.value(forKey: Key.test)
        
        XCTAssertEqual(readValue, writtenValue, "Read and written values must match")
    }
    
    func testSettingNilValue() throws {
        let userDefaults = UserDefaultsTests.cleanUserDefaults()
        defer {
            UserDefaultsTests.removeUserDefaults()
        }
        
        enum Key: String {
            case test
        }
        
        userDefaults.set(1337, forKey: Key.test)
        userDefaults.set(nil as Int?, forKey: Key.test)
        
        let readValue: Int? = userDefaults.value(forKey: Key.test)
        XCTAssertNil(readValue, "Read value should be nil")
    }
    
    func testRemovingValue() throws {
        let userDefaults = UserDefaultsTests.cleanUserDefaults()
        defer {
            UserDefaultsTests.removeUserDefaults()
        }
        
        enum Key: String {
            case test
        }
        
        userDefaults.set(1337, forKey: Key.test)
        userDefaults.removeValue(forKey: Key.test)
        
        let readValue: Int? = userDefaults.value(forKey: Key.test)
        XCTAssertNil(readValue, "Read value should be nil")
    }
    
    
}
