//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import Sodium
import CryptorECC
import HKDF
import DoubleRatchet
import X3DH
import Logging
import CryptoKit

enum CryptoManagerError: Error, CustomStringConvertible {
    case encryptionError
    case decryptionError(Error?)
    case invalidKey

    var description: String {
        switch self {
        case .encryptionError: return "Encryption failed"
        case .decryptionError(let error): return "Decryption failed. Reason: \(error.map { String(describing: $0) } ?? "None")"
        case .invalidKey: return "Invalid key"
        }
    }
}

class CryptoManager: CryptoManagerType {
    let sodium = Sodium()
    
    func generateDatabaseKey(length: Int) -> SecretKey? {
        sodium.randomBytes.buf(length: length).map { SecretKey($0) }
    }
    
    func generateSigningKeyPair() throws -> KeyPair {
        if #available(iOS 14.0, *) {
            let privateSigningKey = P521.Signing.PrivateKey()
            let publicSigningKey = privateSigningKey.publicKey
            
            let privateKeyData = Data(privateSigningKey.pemRepresentation.bytes)
            let publicKeyData = Data(publicSigningKey.pemRepresentation.bytes)
            
            return KeyPair(privateKey: privateKeyData, publicKey: publicKeyData)
        } else {
            let privateSigningKey = try ECPrivateKey.make(for: .secp521r1)
            let publicSigningKey = try privateSigningKey.extractPublicKey()
            
            return KeyPair(privateKey: signingKey(from: privateSigningKey.pemString), publicKey: signingKey(from: publicSigningKey.pemString))
        }
    }

    func signingKeyString(from key: Data) throws -> String {
        guard let keyString = Bytes(key).utf8String else {
            throw CryptoManagerError.invalidKey
        }
        return keyString
    }

    private func signingKey(from pemString: String) -> Data {
        return Data(pemString.bytes)
    }

    func generateGroupKey() -> SecretKey {
        return Data(sodium.aead.xchacha20poly1305ietf.key())
    }

    func tokenKeyForGroup(groupKey: SecretKey, user: User) throws -> SecretKey {
        var inputKeyingMaterial = Bytes()
        inputKeyingMaterial.append(contentsOf: groupKey)
        inputKeyingMaterial.append(contentsOf: user.publicSigningKey)

        let key = try deriveHKDFKey(ikm: inputKeyingMaterial, L: 32)
        return Data(key)
    }
    
    // MARK: Encryption / Decryption

    func encrypt(_ data: Data) throws -> (ciphertext: Ciphertext, secretKey: SecretKey) {
        let secretKey = Data(sodium.aead.xchacha20poly1305ietf.key())
        let ciphertext = try encrypt(data, secretKey: secretKey)
        return (ciphertext: ciphertext, secretKey: secretKey)
    }

    func encrypt(_ data: Data, secretKey: SecretKey) throws -> Ciphertext {
        guard let cipher: Bytes = sodium.aead.xchacha20poly1305ietf.encrypt(message: Bytes(data), secretKey: Bytes(secretKey)) else {
            throw CryptoManagerError.encryptionError
        }
        return Data(cipher)
    }

    func decrypt(encryptedData: Ciphertext, secretKey: SecretKey) throws -> Data {
        guard let plaintext = sodium.aead.xchacha20poly1305ietf.decrypt(nonceAndAuthenticatedCipherText: Bytes(encryptedData), secretKey: Bytes(secretKey)) else {
            throw CryptoManagerError.decryptionError(nil)
        }
        return Data(plaintext)
    }
}
