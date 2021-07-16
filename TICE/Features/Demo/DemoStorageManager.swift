//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation

class DemoStorageManager: DemoStorageManagerType {
    
    let userDefaults: UserDefaults
    let encoder: JSONEncoder
    let decoder: JSONDecoder
    
    enum StorageKey: String {
        case state
    }
    
    init(userDefaults: UserDefaults, encoder: JSONEncoder, decoder: JSONDecoder) {
        self.userDefaults = userDefaults
        self.encoder = encoder
        self.decoder = decoder
    }
    
    func load() throws -> DemoManagerState? {
        guard let data: Data = userDefaults.value(forKey: StorageKey.state) else { return nil }
        return try decoder.decode(DemoManagerState.self, from: data)
    }
    
    func store(state: DemoManagerState) throws {
        let data = try encoder.encode(state)
        userDefaults.set(data, forKey: StorageKey.state)
    }
    
    func deleteAllData() {
        userDefaults.removeValue(forKey: StorageKey.state)
    }
}
