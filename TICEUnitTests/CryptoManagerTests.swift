//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import XCTest
import Sodium
import Clibsodium
import CryptorECC
import HKDF

@testable import TICE

class CryptoManagerTests: XCTestCase {
    var publicKey: PublicKey!
    var secretKey: SecretKey!
    
    var sodium: Sodium!
    
    var cryptoManager: CryptoManager!
    
    override func setUp() {
        super.setUp()
        
        publicKey = """
    -----BEGIN PUBLIC KEY-----
    MIGbMBAGByqGSM49AgEGBSuBBAAjA4GGAAQAFbpq9AOJt5HstjXkiUPX+cpD6Tgk
    nd5SeeD1u3JlfWuY5EScfuuWrJ3VP+B5OCKImfBl2n53Q4ICg2D34N1b80wA4cPV
    02thuiz97m2SNI1jODJ09QHlNQqhbc7pFxhwgAIbTLZXaR3yBw4UbGt7R/VkpC+x
    HWx9m1on3n5MaYhATPc=
    -----END PUBLIC KEY-----
    """.data
        
        secretKey = Data(hex: "bcb44bea011976cf5f5ee846dd9377ffe68ff103272d08448abac40fa2bc75c0")
        
        sodium = Sodium()
        
        cryptoManager = CryptoManager()
    }
    
    func testGenerateDatabaseKey() {
        var length = 16
        let databaseKey1 = cryptoManager.generateDatabaseKey(length: length)
        XCTAssertEqual(databaseKey1?.bytes.count, length)
        
        length = 32
        let databaseKey2 = cryptoManager.generateDatabaseKey(length: length)
        XCTAssertEqual(databaseKey2?.bytes.count, length)
        
        XCTAssertNotEqual(databaseKey1, databaseKey2)
    }
    
    func testGenerateSigningKeyPair() throws {
        let keyPair = try cryptoManager.generateSigningKeyPair()
        
        let privateKey = try ECPrivateKey(key: keyPair.privateKey.utf8String)
        let publicKey = try ECPublicKey(key: keyPair.publicKey.utf8String)
        XCTAssertEqual(try privateKey.extractPublicKey().pemString, publicKey.pemString)
    }
    
    func testSigningKeyString() throws {
        let signingKeyString = try cryptoManager.signingKeyString(from: publicKey)
        
        XCTAssertEqual(signingKeyString, publicKey.utf8String)
    }
    
    func testGenerateGroupKey() {
        let groupKey1 = cryptoManager.generateGroupKey()
        let groupKey2 = cryptoManager.generateGroupKey()
        
        XCTAssertNotEqual(groupKey1, groupKey2)
        XCTAssertEqual(groupKey1.count, Int(crypto_aead_xchacha20poly1305_ietf_KEYBYTES))
    }
    
    func testTokenKeyForGroup() throws {
        let user = User(userId: UserId(), publicSigningKey: publicKey, publicName: nil)
        
        let tokenKeyForGroup = try cryptoManager.tokenKeyForGroup(groupKey: secretKey, user: user)
        
        var ikm = secretKey!
        ikm.append(publicKey)
        XCTAssertEqual(tokenKeyForGroup.bytes, try deriveHKDFKey(ikm: ikm.bytes, L: 32))
    }
    
    func testEncryption() throws {
        let data = "data".data
        
        let cipher = try cryptoManager.encrypt(data, secretKey: secretKey)
        
        guard let plaintext = sodium.aead.xchacha20poly1305ietf.decrypt(nonceAndAuthenticatedCipherText: cipher.bytes, secretKey: secretKey.bytes) else {
            XCTFail()
            return
        }
        XCTAssertEqual(plaintext, data.bytes)
    }
    
    func testEncryptionWithGeneratedKey() throws {
        let data = "data".data
        
        let (cipher1, secretKey1) = try cryptoManager.encrypt(data)
        let (cipher2, secretKey2) = try cryptoManager.encrypt(data)
        
        guard let plaintext1 = sodium.aead.xchacha20poly1305ietf.decrypt(nonceAndAuthenticatedCipherText: cipher1.bytes, secretKey: secretKey1.bytes),
              let plaintext2 = sodium.aead.xchacha20poly1305ietf.decrypt(nonceAndAuthenticatedCipherText: cipher2.bytes, secretKey: secretKey2.bytes) else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(plaintext1, data.bytes)
        XCTAssertEqual(plaintext2, data.bytes)
        
        XCTAssertNotEqual(secretKey1, secretKey2)
    }
    
    func testDecryption() throws {
        let data = "data".data
        
        let cipher: Bytes = sodium.aead.xchacha20poly1305ietf.encrypt(message: data.bytes, secretKey: secretKey.bytes)!
        
        let plaintext = try cryptoManager.decrypt(encryptedData: Data(cipher), secretKey: secretKey)
        XCTAssertEqual(plaintext, data)
    }
}
