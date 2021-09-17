//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import Valet
import GRDB
import protocol DoubleRatchet.MessageKeyCache
import typealias DoubleRatchet.MessageKey

enum CryptoStorageManagerError: Error {
    case keychainInaccessible
    case noDataStored
    case invalidOneTimePrekey
}

class CryptoStorageManager: CryptoStorageManagerType {
    
    let valet: Valet
    let encoder: JSONEncoder
    let decoder: JSONDecoder
    let userDefaults: UserDefaults
    let database: DatabaseWriter
    let oneTimePrekeysMaxCount: Int
    
    @SynchronizedProperty var messageKeyCaches: [ConversationId: MessageKeyCache] = [:]

    enum CryptoStorageKey: String {
        case signingKey
        case identityKey
        case signedPrekey
        case prekeySignature
        case oneTimePrekeys
    }

    init(valet: Valet, userDefaults: UserDefaults, database: DatabaseWriter, encoder: JSONEncoder, decoder: JSONDecoder, oneTimePrekeysMaxCount: Int) {
        self.valet = valet
        self.encoder = encoder
        self.decoder = decoder
        self.userDefaults = userDefaults
        self.database = database
        self.oneTimePrekeysMaxCount = oneTimePrekeysMaxCount
    }

    // MARK: Helper

    private func save(privateKey: PrivateKey, key: CryptoStorageKey) throws {
        guard valet.set(object: privateKey, forKey: key.rawValue) else {
            throw CryptoStorageManagerError.keychainInaccessible
        }
    }

    private func save(publicKey: PublicKey, key: CryptoStorageKey) {
        userDefaults.set(publicKey, forKey: key.rawValue)
    }

    private func save(keyPair: KeyPair, key: CryptoStorageKey) throws {
        try save(privateKey: keyPair.privateKey, key: key)
        save(publicKey: keyPair.publicKey, key: key)
    }

    private func loadPrivateKey(_ key: CryptoStorageKey) -> PrivateKey? {
        valet.object(forKey: key.rawValue)
    }

    private func loadPublicKey(_ key: CryptoStorageKey) -> PublicKey? {
        userDefaults.data(forKey: key.rawValue)
    }

    private func loadKeyPair(_ key: CryptoStorageKey) -> KeyPair? {
        guard let privateKey = loadPrivateKey(key),
            let publicKey = loadPublicKey(key) else {
                return nil
        }
        return KeyPair(privateKey: privateKey, publicKey: publicKey)
    }

    func saveIdentityKeyPair(_ keyPair: KeyPair) throws {
        try save(keyPair: keyPair, key: .identityKey)
    }

    func savePrekeyPair(_ keyPair: KeyPair, signature: Signature) throws {
        try save(keyPair: keyPair, key: .signedPrekey)
        userDefaults.set(signature, forKey: CryptoStorageKey.prekeySignature.rawValue)
    }

    func saveOneTimePrekeyPairs(_ keyPairs: [KeyPair]) throws {
        var deletedRecords: Int?
        try database.write { db in
            for keyPair in keyPairs {
                try OneTimePrekeyPair(keyPair: keyPair).save(db)
            }

            let recordCount = try OneTimePrekeyPair.fetchCount(db)
            let exceedingCount = recordCount - oneTimePrekeysMaxCount

            guard exceedingCount > 0 else { return }

            let idsToDelete = try OneTimePrekeyPair
                .select(Column("id"), as: Int.self)
                .orderByPrimaryKey()
                .limit(exceedingCount)
                .fetchAll(db)

            deletedRecords = try OneTimePrekeyPair
                .filter(idsToDelete.contains(Column("id")))
                .deleteAll(db)
        }
        
        if let deletedRecords = deletedRecords {
            logger.debug("Deleted \(deletedRecords) one-time prekey pair records because we exceeded the threshold of \(oneTimePrekeysMaxCount).")
        }
    }

    func loadIdentityKeyPair() throws -> KeyPair {
        guard let keyPair = loadKeyPair(.identityKey) else {
            throw CryptoStorageManagerError.noDataStored
        }
        return keyPair
    }

    func loadPrekeyPair() throws -> KeyPair {
        guard let keyPair = loadKeyPair(.signedPrekey) else {
            throw CryptoStorageManagerError.noDataStored
        }
        return keyPair
    }

    func loadPrekeySignature() throws -> Signature {
        guard let signature = userDefaults.data(forKey: CryptoStorageKey.prekeySignature.rawValue) else {
            throw CryptoStorageManagerError.noDataStored
        }
        return signature
    }

    func loadPrivateOneTimePrekey(publicKey: PublicKey) throws -> PrivateKey {
        try database.read { db in
            guard let privateKey = try OneTimePrekeyPair.fetchOne(db, key: ["publicKey": publicKey])?.privateKey else {
                logger.info("Didn't find private one-time prekey for public key: \(publicKey.hexEncodedString())")
                throw CryptoStorageManagerError.invalidOneTimePrekey
            }
            return privateKey
        }
    }

    func deleteOneTimePrekeyPair(publicKey: PublicKey) throws {
        return try database.write { db in
            try OneTimePrekeyPair.deleteOne(db, key: ["publicKey": publicKey])
        }
    }

    func save(_ conversationState: ConversationState) throws {
        try database.write { db in
            try conversationState.save(db)
        }
    }

    func loadConversationState(userId: UserId, conversationId: ConversationId) throws -> ConversationState? {
        try database.read { db in
            try ConversationState.fetchOne(db, key: ["userId": userId, "conversationId": conversationId])
        }
    }

    func loadConversationStates() throws -> [ConversationState] {
        try database.read { db in
            try ConversationState.fetchAll(db)
        }
    }
    
    func messageKeyCache(conversationId: ConversationId) throws -> MessageKeyCache {
        if let messageKeyCache = messageKeyCaches[conversationId] {
            return messageKeyCache
        }
        
        let cache = DatabaseMessageKeyCache(conversationId: conversationId, database: database)
        messageKeyCaches[conversationId] = cache
        return cache
    }
    
    func cleanUpCache(entriesOlderThan date: Date) throws {
        return try database.write { db in
            try MessageKeyCacheEntry
                .filter(Column("timestamp") < date)
                .deleteAll(db)
        }
    }
}

extension CryptoStorageManager: DeletableStorageManagerType {
    func deleteAllData() {
        valet.removeObject(forKey: CryptoStorageKey.signedPrekey.rawValue)
        valet.removeObject(forKey: CryptoStorageKey.identityKey.rawValue)

        userDefaults.removeObject(forKey: CryptoStorageKey.signingKey.rawValue)
        userDefaults.removeObject(forKey: CryptoStorageKey.identityKey.rawValue)
        userDefaults.removeObject(forKey: CryptoStorageKey.signedPrekey.rawValue)
        userDefaults.removeObject(forKey: CryptoStorageKey.oneTimePrekeys.rawValue)

        do {
            try database.write { db in
                try db.drop(table: OneTimePrekeyPair.databaseTableName)
                try db.drop(table: ConversationState.databaseTableName)
                try db.drop(table: MessageKeyCacheEntry.databaseTableName)
            }
        } catch {
            logger.error("Failed to delete all data in crypto storage manager: \(String(describing: error))")
        }
    }
}
