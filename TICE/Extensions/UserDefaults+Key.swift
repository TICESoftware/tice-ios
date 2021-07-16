//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation

extension UserDefaults {
    
    func set<T, U: RawRepresentable>(_ value: T?, forKey key: U) where U.RawValue == String {
        set(value, forKey: key.rawValue)
    }

    func value<T, U: RawRepresentable>(forKey key: U) -> T? where U.RawValue == String {
        return value(forKey: key.rawValue) as? T
    }
    
    func removeValue<U: RawRepresentable>(forKey key: U) where U.RawValue == String {
        removeValue(for: key.rawValue)
    }
    
}
