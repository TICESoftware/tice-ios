//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import Logging
import X3DH
import TICEAPIModels
import Sodium
import DoubleRatchet
import CryptorECC
import CryptoKit

enum ConversationCryptoMiddlewareError: LocalizedError, CustomStringConvertible {
    case discardedObsoleteMessage
    case decryptionError
    case conversationNotInitialized
    case maxSkipExceeded
    case oneTimePrekeyMissing

    var description: String {
        switch self {
        case .discardedObsoleteMessage: return "Discarded obsolete message."
        case .conversationNotInitialized: return "Conversation with user not initialized yet."
        case .maxSkipExceeded: return "Skipped too many messages. Ratchet step required."
        case .decryptionError: return "Decryption failed."
        case .oneTimePrekeyMissing: return "No one-time prekey present."
        }
    }
}

class ConversationCryptoMiddleware: ConversationCryptoMiddlewareType {
    let cryptoManager: CryptoManagerType
    let cryptoStorageManager: CryptoStorageManagerType
    
    let handshake: X3DHType
    let doubleRatchetProvider: DoubleRatchetProviderType
    let logger: Logger
    let encoder: JSONEncoder
    let decoder: JSONDecoder
    
    let maxSkip: Int
    let maxCache: Int
    let info: String
    let oneTimePrekeyCount: Int
    
    init(cryptoManager: CryptoManagerType, cryptoStorageManager: CryptoStorageManagerType, handshake: X3DHType, doubleRatchetProvider: DoubleRatchetProviderType, encoder: JSONEncoder, decoder: JSONDecoder, logger: Logger, maxSkip: Int, maxCache: Int, info: String, oneTimePrekeyCount: Int) {
        self.cryptoManager = cryptoManager
        self.cryptoStorageManager = cryptoStorageManager
        self.handshake = handshake
        self.doubleRatchetProvider = doubleRatchetProvider
        self.encoder = encoder
        self.decoder = decoder
        self.logger = logger
        self.maxSkip = maxSkip
        self.maxCache = maxCache
        self.info = info
        self.oneTimePrekeyCount = oneTimePrekeyCount
    }

    func renewHandshakeKeyMaterial(privateSigningKey: PrivateKey) throws -> UserPublicKeys {
        var identityKeyPair: KeyPair
        var prekeyPair: KeyPair
        var prekeySignature: Signature
        
        do {
            guard !CommandLine.arguments.contains("UITESTING") else {
                throw CryptoStorageManagerError.noDataStored
            }
            
            identityKeyPair = try cryptoStorageManager.loadIdentityKeyPair()
            prekeyPair = try cryptoStorageManager.loadPrekeyPair()
            prekeySignature = try cryptoStorageManager.loadPrekeySignature()
        } catch CryptoStorageManagerError.noDataStored {
            logger.info("Renewing handshake key material for the first time. Generating new key material.")
            
            identityKeyPair = try handshake.generateIdentityKeyPair().dataKeyPair
            try cryptoStorageManager.saveIdentityKeyPair(identityKeyPair)
            
            let signedPrekeyPair = try handshake.generateSignedPrekeyPair {
                try self.sign(prekey: Data($0), privateSigningKey: privateSigningKey)
            }
            
            prekeyPair = signedPrekeyPair.keyPair.dataKeyPair
            prekeySignature = signedPrekeyPair.signature
            
            try cryptoStorageManager.savePrekeyPair(prekeyPair, signature: prekeySignature)
        }

        let oneTimePrekeyPairs = try handshake.generateOneTimePrekeyPairs(count: oneTimePrekeyCount).map { $0.dataKeyPair }
        try cryptoStorageManager.saveOneTimePrekeyPairs(oneTimePrekeyPairs)

        let privateSigningKeyString = try cryptoManager.signingKeyString(from: privateSigningKey)
        
        let publicSigningKey: PublicKey
        if #available(iOS 14.0, *) {
            let privateSigningKey = try P521.Signing.PrivateKey(pemRepresentation: privateSigningKeyString)
            publicSigningKey = privateSigningKey.publicKey.pemRepresentation.bytes.dataKey
        } else {
            let privateSigningKey = try ECPrivateKey(key: privateSigningKeyString)
            publicSigningKey = try privateSigningKey.extractPublicKey().pemString.bytes.dataKey
        }

        return UserPublicKeys(signingKey: publicSigningKey, identityKey: identityKeyPair.publicKey, signedPrekey: prekeyPair.publicKey, prekeySignature: prekeySignature, oneTimePrekeys: oneTimePrekeyPairs.map { $0.publicKey })
    }
    
    private func saveConversationState(userId: UserId, conversationId: ConversationId, doubleRatchet: DoubleRatchetType) throws {
        let sessionState = doubleRatchet.sessionState
        
        let rootChainKeyPair = KeyPair(privateKey: Data(sessionState.rootChainKeyPair.secretKey), publicKey: Data(sessionState.rootChainKeyPair.publicKey))
        let conversationState = ConversationState(userId: userId, conversationId: conversationId, rootKey: Data(sessionState.rootKey), rootChainPublicKey: rootChainKeyPair.publicKey, rootChainPrivateKey: rootChainKeyPair.privateKey, rootChainRemotePublicKey: sessionState.rootChainRemotePublicKey?.dataKey, sendingChainKey: sessionState.sendingChainKey?.dataKey, receivingChainKey: sessionState.receivingChainKey?.dataKey, sendMessageNumber: sessionState.sendMessageNumber, receivedMessageNumber: sessionState.receivedMessageNumber, previousSendingChainLength: sessionState.previousSendingChainLength)
        try cryptoStorageManager.save(conversationState)
    }
    
    private func recoverConversationState(conversationState: ConversationState) throws -> DoubleRatchetType {
        let rootChainKeyPair = KeyExchange.KeyPair(publicKey: Bytes(conversationState.rootChainKeyPair.publicKey), secretKey: Bytes(conversationState.rootChainKeyPair.privateKey))
        let sessionState = SessionState(rootKey: Bytes(conversationState.rootKey), rootChainKeyPair: rootChainKeyPair, rootChainRemotePublicKey: conversationState.rootChainRemotePublicKey.map { Bytes($0) }, sendingChainKey: conversationState.sendingChainKey.map { Bytes($0) }, receivingChainKey: conversationState.receivingChainKey.map { Bytes($0) }, sendMessageNumber: conversationState.sendMessageNumber, receivedMessageNumber: conversationState.receivedMessageNumber, previousSendingChainLength: conversationState.previousSendingChainLength, info: info, maxSkip: maxSkip)
        
        let messageKeyCache = try cryptoStorageManager.messageKeyCache(conversationId: conversationState.conversationId)
        let doubleRatchet = doubleRatchetProvider.provideDoubleRatchet(sessionState: sessionState, messageKeyCache: messageKeyCache)
        
        doubleRatchet.setLogger(logger)
        
        return doubleRatchet
    }
    
    func initConversation(with userId: UserId, conversationId: ConversationId, remoteIdentityKey: PublicKey, remoteSignedPrekey: PublicKey, remotePrekeySignature: Signature, remoteOneTimePrekey: PublicKey?, remoteSigningKey: PublicKey) throws -> ConversationInvitation {

        let remoteSigningKeyPemString = try cryptoManager.signingKeyString(from: remoteSigningKey)
        let remoteSigningKey = try ECPublicKey(key: remoteSigningKeyPemString)

        let verifier: PrekeySignatureVerifier = { signature throws in
            try self.verify(prekeySignature: signature, prekey: remoteSignedPrekey, verificationPublicKey: remoteSigningKey)
        }

        let identityKeyPair = try cryptoStorageManager.loadIdentityKeyPair().keyExchangeKeyPair
        let prekey = try cryptoStorageManager.loadPrekeyPair().publicKey

        let keyAgreementInitiation = try handshake.initiateKeyAgreement(remoteIdentityKey: remoteIdentityKey.keyExchangeKey, remotePrekey: remoteSignedPrekey.keyExchangeKey, prekeySignature: remotePrekeySignature, remoteOneTimePrekey: remoteOneTimePrekey?.keyExchangeKey, identityKeyPair: identityKeyPair, prekey: prekey.keyExchangeKey, prekeySignatureVerifier: verifier, info: info)

        let messageKeyCache = try cryptoStorageManager.messageKeyCache(conversationId: conversationId)
        let doubleRatchet = try doubleRatchetProvider.provideDoubleRatchet(keyPair: nil, remotePublicKey: remoteSignedPrekey.keyExchangeKey, sharedSecret: keyAgreementInitiation.sharedSecret, maxSkip: maxSkip, info: info, messageKeyCache: messageKeyCache)
        doubleRatchet.setLogger(logger)
        try saveConversationState(userId: userId, conversationId: conversationId, doubleRatchet: doubleRatchet)

        return ConversationInvitation(identityKey: identityKeyPair.publicKey.dataKey, ephemeralKey: keyAgreementInitiation.ephemeralPublicKey.dataKey, usedOneTimePrekey: remoteOneTimePrekey)
    }

    func processConversationInvitation(_ conversationInvitation: ConversationInvitation, from userId: UserId, conversationId: ConversationId) throws {
        guard let publicOneTimePrekey = conversationInvitation.usedOneTimePrekey else {
            throw ConversationCryptoMiddlewareError.oneTimePrekeyMissing
        }
        let privateOneTimePrekey = try cryptoStorageManager.loadPrivateOneTimePrekey(publicKey: publicOneTimePrekey)

        let identityKeyPair = try cryptoStorageManager.loadIdentityKeyPair().keyExchangeKeyPair
        let prekeyPair = try cryptoStorageManager.loadPrekeyPair().keyExchangeKeyPair
        let oneTimePrekeyPair = KeyPair(privateKey: privateOneTimePrekey, publicKey: publicOneTimePrekey)

        let sharedSecret = try handshake.sharedSecretFromKeyAgreement(remoteIdentityKey: conversationInvitation.identityKey.keyExchangeKey, remoteEphemeralKey: conversationInvitation.ephemeralKey.keyExchangeKey, usedOneTimePrekeyPair: oneTimePrekeyPair.keyExchangeKeyPair, identityKeyPair: identityKeyPair, prekeyPair: prekeyPair, info: info)

        let messageKeyCache = try cryptoStorageManager.messageKeyCache(conversationId: conversationId)
        let doubleRatchet = try doubleRatchetProvider.provideDoubleRatchet(keyPair: prekeyPair, remotePublicKey: nil, sharedSecret: sharedSecret, maxSkip: maxSkip, info: info, messageKeyCache: messageKeyCache)
        doubleRatchet.setLogger(logger)
        try saveConversationState(userId: userId, conversationId: conversationId, doubleRatchet: doubleRatchet)

        try cryptoStorageManager.deleteOneTimePrekeyPair(publicKey: publicOneTimePrekey)
    }

    func conversationExisting(userId: UserId, conversationId: ConversationId) -> Bool {
        do {
            return try cryptoStorageManager.loadConversationState(userId: userId, conversationId: conversationId) != nil
        } catch {
            logger.error("Error loading conversation state for user \(userId) and conversation id \(conversationId).")
            return false
        }
    }

    func conversationFingerprint(ciphertext: Ciphertext) throws -> ConversationFingerprint {
        let encryptedMessage = try decoder.decode(Message.self, from: ciphertext)
        return Data(encryptedMessage.header.publicKey).base64EncodedString()
    }
    
    func encrypt(_ data: Data, for userId: UserId, conversationId: ConversationId) throws -> Ciphertext {
        guard let conversationState = try cryptoStorageManager.loadConversationState(userId: userId, conversationId: conversationId) else {
            throw ConversationCryptoMiddlewareError.conversationNotInitialized
        }
        
        let doubleRatchet = try recoverConversationState(conversationState: conversationState)

        let message = try doubleRatchet.encrypt(plaintext: Bytes(data))
        try saveConversationState(userId: userId, conversationId: conversationId, doubleRatchet: doubleRatchet)

        return try encoder.encode(message)
    }

    private func decrypt(encryptedSecretKey: Ciphertext, from userId: UserId, conversationId: ConversationId) throws -> SecretKey {
        let messageKeyData = try decrypt(encryptedMessage: encryptedSecretKey, from: userId, conversationId: conversationId)
        return SecretKey(messageKeyData)
    }

    private func decrypt(encryptedMessage: Ciphertext, from userId: UserId, conversationId: ConversationId) throws -> Data {
        let encryptedMessage = try decoder.decode(Message.self, from: encryptedMessage)

        guard let conversationState = try cryptoStorageManager.loadConversationState(userId: userId, conversationId: conversationId) else {
            throw ConversationCryptoMiddlewareError.conversationNotInitialized
        }
        
        let doubleRatchet = try recoverConversationState(conversationState: conversationState)

        let plaintext: Bytes
        do {
            plaintext = try doubleRatchet.decrypt(message: encryptedMessage)
        } catch DRError.exceedMaxSkip {
            throw ConversationCryptoMiddlewareError.maxSkipExceeded
        } catch DRError.discardOldMessage {
            throw ConversationCryptoMiddlewareError.discardedObsoleteMessage
        } catch {
            logger.error("Decryption failed: \(error)")
            throw ConversationCryptoMiddlewareError.decryptionError
        }

        try saveConversationState(userId: userId, conversationId: conversationId, doubleRatchet: doubleRatchet)

        return Data(plaintext)
    }

    func decrypt(encryptedData: Ciphertext, encryptedSecretKey: Ciphertext, from userId: UserId, conversationId: ConversationId) throws -> Data {
        let secretKey = try decrypt(encryptedSecretKey: encryptedSecretKey, from: userId, conversationId: conversationId)
        let plaintext = try cryptoManager.decrypt(encryptedData: encryptedData, secretKey: secretKey)

        return plaintext
    }
    
    // MARK: Sign / verify

    private func sign(prekey: PublicKey, privateSigningKey: PrivateKey) throws -> Signature {
        let privateKeyString = try cryptoManager.signingKeyString(from: privateSigningKey)
        let signingKey = try ECPrivateKey(key: privateKeyString)
        let sig = try prekey.sign(with: signingKey)
        return sig.asn1
    }

    private func verify(prekeySignature: Signature, prekey: PublicKey, verificationPublicKey: ECPublicKey) throws -> Bool {
        let sig = try ECSignature(asn1: prekeySignature)
        return sig.verify(plaintext: Data(prekey), using: verificationPublicKey)
    }
}
