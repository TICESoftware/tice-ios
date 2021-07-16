//
//  Copyright © 2018 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation

protocol CryptoManagerType {
    func generateDatabaseKey(length: Int) -> SecretKey?

    func generateSigningKeyPair() throws -> KeyPair
    func generateGroupKey() -> SecretKey

    func signingKeyString(from key: Data) throws -> String
    
    func tokenKeyForGroup(groupKey: SecretKey, user: User) throws -> SecretKey
    
    func encrypt(_ data: Data) throws -> (ciphertext: Ciphertext, secretKey: SecretKey)
    func encrypt(_ data: Data, secretKey: SecretKey) throws -> Ciphertext
    func decrypt(encryptedData: Data, secretKey: SecretKey) throws -> Data
}
