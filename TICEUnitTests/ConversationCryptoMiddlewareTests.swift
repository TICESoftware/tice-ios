//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import XCTest
import Cuckoo
import Logging
import Sodium
import TICEAPIModels
import CryptorECC

@testable import TICE
@testable import X3DH
@testable import DoubleRatchet

class ConversationCryptoMiddlewareTests: XCTestCase {
    var cryptoManager: MockCryptoManagerType!
    var cryptoStorageManager: MockCryptoStorageManagerType!
    var handshake: MockX3DHType!
    var doubleRatchetProvider: MockDoubleRatchetProviderType!
    var doubleRatchet: MockDoubleRatchetType!
    
    var privateKey: PrivateKey!
    var publicKey: PublicKey!
    
    var conversationCryptoMiddleware: ConversationCryptoMiddleware!
    
    override func setUp() {
        super.setUp()
        
        cryptoManager = MockCryptoManagerType()
        cryptoStorageManager = MockCryptoStorageManagerType()
        handshake = MockX3DHType()
        doubleRatchetProvider = MockDoubleRatchetProviderType()
        doubleRatchet = MockDoubleRatchetType()
        
        privateKey = """
    -----BEGIN EC PRIVATE KEY-----
    MIHcAgEBBEIAgHEAuA8gfGnNUqYGYo2QgShxhd6MFxfig/o0KKPq9MScpf8/AMxv
    kVS5sJxCW2K7lnSs8aynlXcQrfAmt4ybfoOgBwYFK4EEACOhgYkDgYYABAAVumr0
    A4m3key2NeSJQ9f5ykPpOCSd3lJ54PW7cmV9a5jkRJx+65asndU/4Hk4IoiZ8GXa
    fndDggKDYPfg3VvzTADhw9XTa2G6LP3ubZI0jWM4MnT1AeU1CqFtzukXGHCAAhtM
    tldpHfIHDhRsa3tH9WSkL7EdbH2bWifefkxpiEBM9w==
    -----END EC PRIVATE KEY-----
    """.data
        
        publicKey = """
    -----BEGIN PUBLIC KEY-----
    MIGbMBAGByqGSM49AgEGBSuBBAAjA4GGAAQAFbpq9AOJt5HstjXkiUPX+cpD6Tgk
    nd5SeeD1u3JlfWuY5EScfuuWrJ3VP+B5OCKImfBl2n53Q4ICg2D34N1b80wA4cPV
    02thuiz97m2SNI1jODJ09QHlNQqhbc7pFxhwgAIbTLZXaR3yBw4UbGt7R/VkpC+x
    HWx9m1on3n5MaYhATPc=
    -----END PUBLIC KEY-----
    """.data
        
        let logger = Logger(label: "software.tice.TICE.conversationCryptoMiddlewareTestLogging")
        
        conversationCryptoMiddleware = ConversationCryptoMiddleware(
            cryptoManager: cryptoManager,
            cryptoStorageManager: cryptoStorageManager,
            handshake: handshake,
            doubleRatchetProvider: doubleRatchetProvider,
            encoder: JSONEncoder(),
            decoder: JSONDecoder(),
            logger: logger,
            maxSkip: 10,
            maxCache: 10,
            info: "info",
            oneTimePrekeyCount: 10
        )
    }
    
    func testCreateNewHandshakeKeyMaterial() throws {
        stub(cryptoStorageManager) { stub in
            when(stub.loadIdentityKeyPair()).thenThrow(CryptoStorageManagerError.noDataStored)
        }
        
        let identityPair = KeyExchange.KeyPair(publicKey: "publicIdentityKey".bytes, secretKey: "secretIdentityKey".bytes)
        let prekeyPair = KeyExchange.KeyPair(publicKey: "publicPrekey".bytes, secretKey: "secretPrekey".bytes)
        let signedPrekeyPair = X3DH.SignedPrekeyPair(keyPair: prekeyPair, signature: "signature".data)
        let oneTimePrekeyPair = TICE.KeyPair(privateKey: "privateOneTimePrekey".data, publicKey: "publicOneTimePrekey".data)
        stub(handshake) { stub in
            when(stub.generateIdentityKeyPair()).thenReturn(identityPair)
            when(stub.generateSignedPrekeyPair(signer: any())).then { signer in
                let dummyKey = "test".data
                let signature = try signer(dummyKey.bytes)
                
                XCTAssertTrue(try ECSignature(asn1: signature).verify(plaintext: dummyKey, using: ECPublicKey(key: self.publicKey.utf8String)))
                return signedPrekeyPair
            }
            when(stub.generateOneTimePrekeyPairs(count: 10)).thenReturn([oneTimePrekeyPair.keyExchangeKeyPair])
        }
        
        stub(cryptoStorageManager) { stub in
            when(stub.saveIdentityKeyPair(identityPair.dataKeyPair)).thenDoNothing()
            when(stub.savePrekeyPair(signedPrekeyPair.keyPair.dataKeyPair, signature: signedPrekeyPair.signature)).thenDoNothing()
            when(stub.saveOneTimePrekeyPairs([oneTimePrekeyPair])).thenDoNothing()
        }
        
        stub(cryptoManager) { stub in
            when(stub.signingKeyString(from: privateKey)).thenReturn(privateKey.utf8String)
        }
        
        let userPublicKeys = try conversationCryptoMiddleware.renewHandshakeKeyMaterial(privateSigningKey: privateKey)
        
        XCTAssertEqual(userPublicKeys.signingKey, publicKey)
        XCTAssertEqual(userPublicKeys.identityKey, identityPair.dataKeyPair.publicKey)
        XCTAssertEqual(userPublicKeys.signedPrekey, signedPrekeyPair.keyPair.dataKeyPair.publicKey)
        XCTAssertEqual(userPublicKeys.prekeySignature, signedPrekeyPair.signature)
        XCTAssertEqual(userPublicKeys.oneTimePrekeys, [oneTimePrekeyPair.publicKey])
        
        verify(handshake).generateIdentityKeyPair()
        verify(handshake).generateSignedPrekeyPair(signer: any())
        verify(handshake).generateOneTimePrekeyPairs(count: 10)
        
        verify(cryptoStorageManager).saveIdentityKeyPair(any())
        verify(cryptoStorageManager).savePrekeyPair(any(), signature: any())
        verify(cryptoStorageManager).saveOneTimePrekeyPairs(any())
    }
    
    func testRenewHandshakeKeyMaterial() throws {
        let prekeyPair = TICE.KeyPair(privateKey: "privatePrekey".data, publicKey: "publicPrekey".data)
        let prekeySignature = "signature".data
        
        stub(cryptoStorageManager) { stub in
            when(stub.loadIdentityKeyPair()).thenReturn(TICE.KeyPair(privateKey: privateKey, publicKey: publicKey))
            when(stub.loadPrekeyPair()).thenReturn(prekeyPair)
            when(stub.loadPrekeySignature()).thenReturn(prekeySignature)
        }

        let oneTimePrekeyPair = TICE.KeyPair(privateKey: "privateOneTimePrekey".data, publicKey: "publicOneTimePrekey".data)
        stub(handshake) { stub in
            when(stub.generateOneTimePrekeyPairs(count: 10)).thenReturn([oneTimePrekeyPair.keyExchangeKeyPair])
        }
        
        stub(cryptoStorageManager) { stub in
            when(stub.saveOneTimePrekeyPairs([oneTimePrekeyPair])).thenDoNothing()
        }
        
        stub(cryptoManager) { stub in
            when(stub.signingKeyString(from: privateKey)).thenReturn(privateKey.utf8String)
        }
        
        let userPublicKeys = try conversationCryptoMiddleware.renewHandshakeKeyMaterial(privateSigningKey: privateKey)
        
        XCTAssertEqual(userPublicKeys.signingKey, publicKey)
        XCTAssertEqual(userPublicKeys.identityKey, publicKey)
        XCTAssertEqual(userPublicKeys.signedPrekey, prekeyPair.publicKey)
        XCTAssertEqual(userPublicKeys.prekeySignature, prekeySignature)
        XCTAssertEqual(userPublicKeys.oneTimePrekeys, [oneTimePrekeyPair.publicKey])
        

        verify(handshake).generateOneTimePrekeyPairs(count: 10)

        verify(cryptoStorageManager).saveOneTimePrekeyPairs(any())
    }
    
    func testInitConversation() throws {
        let userId = UserId()
        let conversationId = ConversationId()
        
        stub(cryptoManager) { stub in
            when(stub.signingKeyString(from: publicKey)).thenReturn(publicKey.utf8String)
        }
        
        let identityKeyPair = TICE.KeyPair(privateKey: "privateIdentityKey".data, publicKey: "publicIdentityKey".data)
        let prekeyPair = TICE.KeyPair(privateKey: "privatePrekey".data, publicKey: "publicPrekey".data)
        
        let messageKeyCache = MockMessageKeyCache()
        let sessionState = SessionState(
            rootKey: "rootKey".bytes,
            rootChainKeyPair: KeyExchange.KeyPair(publicKey: "rootChainPublicKey".bytes, secretKey: "rootChainSecretKey".bytes),
            rootChainRemotePublicKey: "rootChainRemotePublicKey".bytes,
            sendingChainKey: "sendingChainKey".bytes,
            receivingChainKey: "receivingChainKey".bytes,
            sendMessageNumber: 2,
            receivedMessageNumber: 2,
            previousSendingChainLength: 2,
            info: "sessionInfo",
            maxSkip: 2
        )
        
        stub(doubleRatchet) { stub in
            when(stub.setLogger(any())).thenDoNothing()
            when(stub.sessionState.get).thenReturn(sessionState)
        }
        
        let expectedConversationState = ConversationState(
            userId: userId,
            conversationId: conversationId,
            rootKey: sessionState.rootKey.dataKey,
            rootChainPublicKey: sessionState.rootChainKeyPair.dataKeyPair.publicKey,
            rootChainPrivateKey: sessionState.rootChainKeyPair.dataKeyPair.privateKey,
            rootChainRemotePublicKey: sessionState.rootChainRemotePublicKey?.dataKey,
            sendingChainKey: sessionState.sendingChainKey?.dataKey,
            receivingChainKey: sessionState.receivingChainKey?.dataKey,
            sendMessageNumber: sessionState.sendMessageNumber,
            receivedMessageNumber: sessionState.receivedMessageNumber,
            previousSendingChainLength: sessionState.previousSendingChainLength
        )
        stub(cryptoStorageManager) { stub in
            when(stub.loadIdentityKeyPair()).thenReturn(identityKeyPair)
            when(stub.loadPrekeyPair()).thenReturn(prekeyPair)
            when(stub.messageKeyCache(conversationId: conversationId)).thenReturn(messageKeyCache)
            when(stub.save(expectedConversationState)).thenDoNothing()
        }
        
        let remoteIdentityKey = "remoteIdentityKey".data
        let remotePrekey = "remotePrekey".data
        let remotePrekeySignature = try remotePrekey.sign(with: ECPrivateKey(key: privateKey.utf8String)).asn1
        let remoteOneTimePrekey = "oneTimePrekey".data
        
        let keyAgreementInitiation = X3DH.KeyAgreementInitiation(sharedSecret: "sharedSecret".bytes, associatedData: Bytes(), ephemeralPublicKey: "ephemeralPublicKey".bytes)
        stub(handshake) { stub in
            when(stub.initiateKeyAgreement(
                    remoteIdentityKey: remoteIdentityKey.keyExchangeKey,
                    remotePrekey: remotePrekey.keyExchangeKey,
                    prekeySignature: remotePrekeySignature,
                    remoteOneTimePrekey: remoteOneTimePrekey.keyExchangeKey as KeyExchange.PublicKey?,
                    identityKeyPair: identityKeyPair.keyExchangeKeyPair,
                    prekey: prekeyPair.keyExchangeKeyPair.publicKey,
                    prekeySignatureVerifier: any(),
                    info: "info")
            ).then { _, _, _, _, _, _, verifier, _ in
                XCTAssertTrue(try verifier(remotePrekeySignature))
                return keyAgreementInitiation
            }
        }
        
        stub(doubleRatchetProvider) { stub in
            when(stub.provideDoubleRatchet(
                keyPair: nil as KeyExchange.KeyPair?,
                remotePublicKey: remotePrekey.keyExchangeKey,
                sharedSecret: keyAgreementInitiation.sharedSecret,
                maxSkip: 10,
                info: "info",
                messageKeyCache: any()
            )).thenReturn(doubleRatchet)
        }
        
        let conversationInvitation = try conversationCryptoMiddleware.initConversation(
            with: userId,
            conversationId: conversationId,
            remoteIdentityKey: remoteIdentityKey,
            remoteSignedPrekey: remotePrekey,
            remotePrekeySignature: remotePrekeySignature,
            remoteOneTimePrekey: remoteOneTimePrekey,
            remoteSigningKey: publicKey
        )
        
        XCTAssertEqual(conversationInvitation.identityKey, identityKeyPair.publicKey)
        XCTAssertEqual(conversationInvitation.ephemeralKey, keyAgreementInitiation.ephemeralPublicKey.dataKey)
        XCTAssertEqual(conversationInvitation.usedOneTimePrekey, remoteOneTimePrekey)
        
        verify(handshake).initiateKeyAgreement(remoteIdentityKey: any(), remotePrekey: any(), prekeySignature: any(), remoteOneTimePrekey: any(), identityKeyPair: any(), prekey: any(), prekeySignatureVerifier: any(), info: any())
        verify(doubleRatchetProvider).provideDoubleRatchet(keyPair: any(), remotePublicKey: any(), sharedSecret: any(), maxSkip: any(), info: any(), messageKeyCache: any())
        verify(doubleRatchet).setLogger(any())
        verify(cryptoStorageManager).save(any())
    }
    
    func testInitConversationInvalidPrekeySignature() throws {
        let userId = UserId()
        let conversationId = ConversationId()
        
        stub(cryptoManager) { stub in
            when(stub.signingKeyString(from: publicKey)).thenReturn(publicKey.utf8String)
        }
        
        let identityKeyPair = TICE.KeyPair(privateKey: "privateIdentityKey".data, publicKey: "publicIdentityKey".data)
        let prekeyPair = TICE.KeyPair(privateKey: "privatePrekey".data, publicKey: "publicPrekey".data)
        
        stub(cryptoStorageManager) { stub in
            when(stub.loadIdentityKeyPair()).thenReturn(identityKeyPair)
            when(stub.loadPrekeyPair()).thenReturn(prekeyPair)
        }
        
        let remoteIdentityKey = "remoteIdentityKey".data
        let remotePrekey = "remotePrekey".data
        let remotePrekeySignature = try remotePrekey.sign(with: ECPrivateKey.make(for: .secp521r1)).asn1
        let remoteOneTimePrekey = "oneTimePrekey".data
        
        stub(handshake) { stub in
            when(stub.initiateKeyAgreement(
                    remoteIdentityKey: remoteIdentityKey.keyExchangeKey,
                    remotePrekey: remotePrekey.keyExchangeKey,
                    prekeySignature: remotePrekeySignature,
                    remoteOneTimePrekey: remoteOneTimePrekey.keyExchangeKey as KeyExchange.PublicKey?,
                    identityKeyPair: identityKeyPair.keyExchangeKeyPair,
                    prekey: prekeyPair.keyExchangeKeyPair.publicKey,
                    prekeySignatureVerifier: any(),
                    info: "info")
            ).then { _, _, _, _, _, _, verifier, _ in
                XCTAssertFalse(try verifier(remotePrekeySignature))
                throw X3DHError.invalidPrekeySignature
            }
        }
        
        XCTAssertThrowsSpecificError(_ = try conversationCryptoMiddleware.initConversation(
            with: userId,
            conversationId: conversationId,
            remoteIdentityKey: remoteIdentityKey,
            remoteSignedPrekey: remotePrekey,
            remotePrekeySignature: remotePrekeySignature,
            remoteOneTimePrekey: remoteOneTimePrekey,
            remoteSigningKey: publicKey
        ), X3DHError.invalidPrekeySignature)
        
        verify(handshake).initiateKeyAgreement(remoteIdentityKey: any(), remotePrekey: any(), prekeySignature: any(), remoteOneTimePrekey: any(), identityKeyPair: any(), prekey: any(), prekeySignatureVerifier: any(), info: any())
    }
    
    func testProcessConversationInvitation() throws {
        let userId = UserId()
        let conversationId = ConversationId()
        
        let identityKeyPair = TICE.KeyPair(privateKey: "privateIdentityKey".data, publicKey: "publicIdentityKey".data)
        let prekeyPair = TICE.KeyPair(privateKey: "privatePrekey".data, publicKey: "publicPrekey".data)
        let privateOneTimePrekey = "privateOneTimePrekey".data
        
        let remoteIdentityKey = "remoteIdentityKey".data
        let remoteEphemeralKey = "remoteEphemeralKey".data
        let usedOneTimePrekey = "usedOneTimePrekey".data
        let oneTimePrekeypair = KeyExchange.KeyPair(publicKey: usedOneTimePrekey.keyExchangeKey, secretKey: privateOneTimePrekey.keyExchangeKey)
        let conversationInvitation = ConversationInvitation(identityKey: remoteIdentityKey, ephemeralKey: remoteEphemeralKey, usedOneTimePrekey: usedOneTimePrekey)
        
        let sharedSecret = "sharedSecret".bytes
        
        stub(handshake) { stub in
            when(stub.sharedSecretFromKeyAgreement(
                    remoteIdentityKey: remoteIdentityKey.keyExchangeKey,
                    remoteEphemeralKey: remoteEphemeralKey.keyExchangeKey,
                    usedOneTimePrekeyPair: oneTimePrekeypair,
                    identityKeyPair: identityKeyPair.keyExchangeKeyPair,
                    prekeyPair: prekeyPair.keyExchangeKeyPair,
                    info: "info")
            ).thenReturn(sharedSecret)
        }
        
        let messageKeyCache = MockMessageKeyCache()
        let sessionState = SessionState(
            rootKey: "rootKey".bytes,
            rootChainKeyPair: KeyExchange.KeyPair(publicKey: "rootChainPublicKey".bytes, secretKey: "rootChainSecretKey".bytes),
            rootChainRemotePublicKey: "rootChainRemotePublicKey".bytes,
            sendingChainKey: "sendingChainKey".bytes,
            receivingChainKey: "receivingChainKey".bytes,
            sendMessageNumber: 2,
            receivedMessageNumber: 2,
            previousSendingChainLength: 2,
            info: "sessionInfo",
            maxSkip: 2
        )
        
        stub(doubleRatchetProvider) { stub in
            when(stub.provideDoubleRatchet(
                keyPair: prekeyPair.keyExchangeKeyPair,
                remotePublicKey: nil as KeyExchange.PublicKey?,
                sharedSecret: sharedSecret,
                maxSkip: 10,
                info: "info",
                messageKeyCache: any()
            )).thenReturn(doubleRatchet)
        }
        
        stub(doubleRatchet) { stub in
            when(stub.setLogger(any())).thenDoNothing()
            when(stub.sessionState.get).thenReturn(sessionState)
        }
        
        let expectedConversationState = ConversationState(
            userId: userId,
            conversationId: conversationId,
            rootKey: sessionState.rootKey.dataKey,
            rootChainPublicKey: sessionState.rootChainKeyPair.dataKeyPair.publicKey,
            rootChainPrivateKey: sessionState.rootChainKeyPair.dataKeyPair.privateKey,
            rootChainRemotePublicKey: sessionState.rootChainRemotePublicKey?.dataKey,
            sendingChainKey: sessionState.sendingChainKey?.dataKey,
            receivingChainKey: sessionState.receivingChainKey?.dataKey,
            sendMessageNumber: sessionState.sendMessageNumber,
            receivedMessageNumber: sessionState.receivedMessageNumber,
            previousSendingChainLength: sessionState.previousSendingChainLength
        )
        
        stub(cryptoStorageManager) { stub in
            when(stub.loadIdentityKeyPair()).thenReturn(identityKeyPair)
            when(stub.loadPrekeyPair()).thenReturn(prekeyPair)
            when(stub.loadPrivateOneTimePrekey(publicKey: usedOneTimePrekey)).thenReturn(privateOneTimePrekey)
            when(stub.messageKeyCache(conversationId: conversationId)).thenReturn(messageKeyCache)
            when(stub.save(expectedConversationState)).thenDoNothing()
            when(stub.deleteOneTimePrekeyPair(publicKey: usedOneTimePrekey)).thenDoNothing()
        }
        
        try conversationCryptoMiddleware.processConversationInvitation(conversationInvitation, from: userId, conversationId: conversationId)
        
        verify(handshake).sharedSecretFromKeyAgreement(remoteIdentityKey: any(), remoteEphemeralKey: any(), usedOneTimePrekeyPair: any(), identityKeyPair: any(), prekeyPair: any(), info: any())
        verify(doubleRatchetProvider).provideDoubleRatchet(keyPair: any(), remotePublicKey: any(), sharedSecret: any(), maxSkip: any(), info: any(), messageKeyCache: any())
        verify(doubleRatchet).setLogger(any())
        verify(cryptoStorageManager).save(any())
        verify(cryptoStorageManager).deleteOneTimePrekeyPair(publicKey: any())
    }
    
    func testProcessConversationInvitationWithoutOneTimePrekey() throws {
        let conversationInvitation = ConversationInvitation(identityKey: "".data, ephemeralKey: "".data, usedOneTimePrekey: nil)
        
        XCTAssertThrowsSpecificError(
            try conversationCryptoMiddleware.processConversationInvitation(conversationInvitation, from: UserId(), conversationId: ConversationId()), ConversationCryptoMiddlewareError.oneTimePrekeyMissing)
    }
    
    func testConversationExisting() throws {
        let userId = UserId()
        let conversationId = ConversationId()
        
        let mockConversationState = ConversationState(
            userId: userId,
            conversationId: conversationId,
            rootKey: "".data,
            rootChainPublicKey: "".data,
            rootChainPrivateKey: "".data,
            rootChainRemotePublicKey: nil,
            sendingChainKey: nil,
            receivingChainKey: nil,
            sendMessageNumber: 0,
            receivedMessageNumber: 0,
            previousSendingChainLength: 0
        )
        stub(cryptoStorageManager) { stub in
            when(stub.loadConversationState(userId: userId, conversationId: conversationId)).thenReturn(nil, mockConversationState)
        }
        
        XCTAssertFalse(conversationCryptoMiddleware.conversationExisting(userId: userId, conversationId: conversationId))
        XCTAssertTrue(conversationCryptoMiddleware.conversationExisting(userId: userId, conversationId: conversationId))
    }
    
    func testConversationFingerprint() throws {
        let header = Header(publicKey: "publicKey".bytes, numberOfMessagesInPreviousSendingChain: 10, messageNumber: 10)
        let message = Message(header: header, cipher: "cipher".bytes)
        let encodedMessage = try JSONEncoder().encode(message)
        
        XCTAssertEqual(try conversationCryptoMiddleware.conversationFingerprint(ciphertext: encodedMessage), header.publicKey.dataKey.base64EncodedString())
    }
    
    func testEncryption() throws {
        let userId = UserId()
        let conversationId = ConversationId()
        let plaintext = "plaintext".data
        
        let conversationStateBeforeEncryption = ConversationState(
            userId: userId,
            conversationId: conversationId,
            rootKey: "rootKey".data,
            rootChainPublicKey: "rootChainPublicKey".data,
            rootChainPrivateKey: "rootChainPrivateKey".data,
            rootChainRemotePublicKey: "rootChainRemotePublicKey".data,
            sendingChainKey: "sendingChainKey".data,
            receivingChainKey: "receivingChainKey".data,
            sendMessageNumber: 2,
            receivedMessageNumber: 2,
            previousSendingChainLength: 2
        )
        
        let expectedSessionStateBeforeEncryption = SessionState(
            rootKey: conversationStateBeforeEncryption.rootKey.keyExchangeKey,
            rootChainKeyPair: conversationStateBeforeEncryption.rootChainKeyPair.keyExchangeKeyPair,
            rootChainRemotePublicKey: conversationStateBeforeEncryption.rootChainRemotePublicKey?.keyExchangeKey,
            sendingChainKey: conversationStateBeforeEncryption.sendingChainKey?.keyExchangeKey,
            receivingChainKey: conversationStateBeforeEncryption.receivingChainKey?.keyExchangeKey,
            sendMessageNumber: conversationStateBeforeEncryption.sendMessageNumber,
            receivedMessageNumber: conversationStateBeforeEncryption.receivedMessageNumber,
            previousSendingChainLength: conversationStateBeforeEncryption.previousSendingChainLength,
            info: "info",
            maxSkip: 10
        )
        
        let sessionStateAfterEncryption = SessionState(
            rootKey: "rootKey2".bytes,
            rootChainKeyPair: KeyExchange.KeyPair(publicKey: "rootChainPublicKey2".bytes, secretKey: "rootChainPrivateKey2".bytes),
            rootChainRemotePublicKey: "rootChainRemotePublicKey2".bytes,
            sendingChainKey: "sendingChainKey".bytes,
            receivingChainKey: "receivingChainKey".bytes,
            sendMessageNumber: 11,
            receivedMessageNumber: 11,
            previousSendingChainLength: 11,
            info: "info",
            maxSkip: 10
        )
        
        let expectedConversationStateAfterEncryption = ConversationState(
            userId: userId,
            conversationId: conversationId,
            rootKey: sessionStateAfterEncryption.rootKey.dataKey,
            rootChainPublicKey: sessionStateAfterEncryption.rootChainKeyPair.dataKeyPair.publicKey,
            rootChainPrivateKey: sessionStateAfterEncryption.rootChainKeyPair.dataKeyPair.privateKey,
            rootChainRemotePublicKey: sessionStateAfterEncryption.rootChainRemotePublicKey?.dataKey,
            sendingChainKey: sessionStateAfterEncryption.sendingChainKey?.dataKey,
            receivingChainKey: sessionStateAfterEncryption.receivingChainKey?.dataKey,
            sendMessageNumber: sessionStateAfterEncryption.sendMessageNumber,
            receivedMessageNumber: sessionStateAfterEncryption.receivedMessageNumber,
            previousSendingChainLength: sessionStateAfterEncryption.previousSendingChainLength
        )
        
        let messageKeyCache = MockMessageKeyCache()
        stub(cryptoStorageManager) { stub in
            when(stub.loadConversationState(userId: userId, conversationId: conversationId)).thenReturn(conversationStateBeforeEncryption)
            when(stub.messageKeyCache(conversationId: conversationId)).thenReturn(messageKeyCache)
            when(stub.save(expectedConversationStateAfterEncryption)).thenDoNothing()
        }
        
        stub(doubleRatchetProvider) { stub in
            when(stub.provideDoubleRatchet(sessionState: expectedSessionStateBeforeEncryption, messageKeyCache: any())).thenReturn(doubleRatchet)
        }
        
        let header = Header(publicKey: "publicKey".bytes, numberOfMessagesInPreviousSendingChain: 10, messageNumber: 10)
        let message = Message(header: header, cipher: "ciphertext".bytes)
        
        stub(doubleRatchet) { stub in
            when(stub.setLogger(any())).thenDoNothing()
            when(stub.encrypt(plaintext: plaintext.bytes)).thenReturn(message)
            when(stub.sessionState.get).thenReturn(sessionStateAfterEncryption)
        }
        
        let ciphertext = try conversationCryptoMiddleware.encrypt(plaintext, for: userId, conversationId: conversationId)
        
        XCTAssertEqual(ciphertext, try JSONEncoder().encode(message))
        
        verify(cryptoStorageManager).loadConversationState(userId: userId, conversationId: conversationId)
        verify(doubleRatchetProvider).provideDoubleRatchet(sessionState: any(), messageKeyCache: any())
        verify(doubleRatchet).encrypt(plaintext: plaintext.bytes)
        verify(cryptoStorageManager).save(any())
    }
    
    func testEncryptionUnknownConversation() throws {
        stub(cryptoStorageManager) { stub in
            when(stub.loadConversationState(userId: any(), conversationId: any())).thenReturn(nil)
        }
        
        XCTAssertThrowsSpecificError(_ = try conversationCryptoMiddleware.encrypt("".data, for: UserId(), conversationId: ConversationId()), ConversationCryptoMiddlewareError.conversationNotInitialized)
    }
    
    func testDecryption() throws {
        let userId = UserId()
        let conversationId = ConversationId()
        
        let header = Header(publicKey: "publicKey".bytes, numberOfMessagesInPreviousSendingChain: 10, messageNumber: 10)
        let message = Message(header: header, cipher: "ciphertext".bytes)
        let encryptedSecretKey = try JSONEncoder().encode(message)
        let secretKey = "secretKey".data
        let encryptedMessage = "encryptedMessage".data
        let plaintextMessage = "plaintext".data
        
        let conversationStateBeforeDecryption = ConversationState(
            userId: userId,
            conversationId: conversationId,
            rootKey: "rootKey".data,
            rootChainPublicKey: "rootChainPublicKey".data,
            rootChainPrivateKey: "rootChainPrivateKey".data,
            rootChainRemotePublicKey: "rootChainRemotePublicKey".data,
            sendingChainKey: "sendingChainKey".data,
            receivingChainKey: "receivingChainKey".data,
            sendMessageNumber: 2,
            receivedMessageNumber: 2,
            previousSendingChainLength: 2
        )
        
        let expectedSessionStateBeforeDecryption = SessionState(
            rootKey: conversationStateBeforeDecryption.rootKey.keyExchangeKey,
            rootChainKeyPair: conversationStateBeforeDecryption.rootChainKeyPair.keyExchangeKeyPair,
            rootChainRemotePublicKey: conversationStateBeforeDecryption.rootChainRemotePublicKey?.keyExchangeKey,
            sendingChainKey: conversationStateBeforeDecryption.sendingChainKey?.keyExchangeKey,
            receivingChainKey: conversationStateBeforeDecryption.receivingChainKey?.keyExchangeKey,
            sendMessageNumber: conversationStateBeforeDecryption.sendMessageNumber,
            receivedMessageNumber: conversationStateBeforeDecryption.receivedMessageNumber,
            previousSendingChainLength: conversationStateBeforeDecryption.previousSendingChainLength,
            info: "info",
            maxSkip: 10
        )
        
        let sessionStateAfterDecryption = SessionState(
            rootKey: "rootKey2".bytes,
            rootChainKeyPair: KeyExchange.KeyPair(publicKey: "rootChainPublicKey2".bytes, secretKey: "rootChainPrivateKey2".bytes),
            rootChainRemotePublicKey: "rootChainRemotePublicKey2".bytes,
            sendingChainKey: "sendingChainKey".bytes,
            receivingChainKey: "receivingChainKey".bytes,
            sendMessageNumber: 11,
            receivedMessageNumber: 11,
            previousSendingChainLength: 11,
            info: "info",
            maxSkip: 10
        )
        
        let expectedConversationStateAfterDecryption = ConversationState(
            userId: userId,
            conversationId: conversationId,
            rootKey: sessionStateAfterDecryption.rootKey.dataKey,
            rootChainPublicKey: sessionStateAfterDecryption.rootChainKeyPair.dataKeyPair.publicKey,
            rootChainPrivateKey: sessionStateAfterDecryption.rootChainKeyPair.dataKeyPair.privateKey,
            rootChainRemotePublicKey: sessionStateAfterDecryption.rootChainRemotePublicKey?.dataKey,
            sendingChainKey: sessionStateAfterDecryption.sendingChainKey?.dataKey,
            receivingChainKey: sessionStateAfterDecryption.receivingChainKey?.dataKey,
            sendMessageNumber: sessionStateAfterDecryption.sendMessageNumber,
            receivedMessageNumber: sessionStateAfterDecryption.receivedMessageNumber,
            previousSendingChainLength: sessionStateAfterDecryption.previousSendingChainLength
        )
        
        let messageKeyCache = MockMessageKeyCache()
        stub(cryptoStorageManager) { stub in
            when(stub.loadConversationState(userId: userId, conversationId: conversationId)).thenReturn(conversationStateBeforeDecryption)
            when(stub.messageKeyCache(conversationId: conversationId)).thenReturn(messageKeyCache)
            when(stub.save(expectedConversationStateAfterDecryption)).thenDoNothing()
        }
        
        stub(doubleRatchetProvider) { stub in
            when(stub.provideDoubleRatchet(sessionState: expectedSessionStateBeforeDecryption, messageKeyCache: any())).thenReturn(doubleRatchet)
        }
        
        stub(doubleRatchet) { stub in
            when(stub.setLogger(any())).thenDoNothing()
            when(stub.decrypt(message: message)).thenReturn(secretKey.bytes)
            when(stub.sessionState.get).thenReturn(sessionStateAfterDecryption)
        }
        
        stub(cryptoManager) { stub in
            when(stub.decrypt(encryptedData: encryptedMessage, secretKey: secretKey)).thenReturn(plaintextMessage)
        }
        
        let decryptedPlaintext = try conversationCryptoMiddleware.decrypt(encryptedData: encryptedMessage, encryptedSecretKey: encryptedSecretKey, from: userId, conversationId: conversationId)
        
        XCTAssertEqual(decryptedPlaintext, plaintextMessage)
        
        verify(cryptoStorageManager).loadConversationState(userId: userId, conversationId: conversationId)
        verify(doubleRatchetProvider).provideDoubleRatchet(sessionState: any(), messageKeyCache: any())
        verify(doubleRatchet).decrypt(message: any())
        verify(cryptoStorageManager).save(any())
    }
    
    func testDecryptionUnknownConversation() throws {
        stub(cryptoStorageManager) { stub in
            when(stub.loadConversationState(userId: any(), conversationId: any())).thenReturn(nil)
        }
        
        let header = Header(publicKey: "publicKey".bytes, numberOfMessagesInPreviousSendingChain: 10, messageNumber: 10)
        let message = Message(header: header, cipher: "ciphertext".bytes)
        let encryptedSecretKey = try JSONEncoder().encode(message)
        
        XCTAssertThrowsSpecificError(_ = try conversationCryptoMiddleware.decrypt(encryptedData: "".data, encryptedSecretKey: encryptedSecretKey, from: UserId(), conversationId: ConversationId()), ConversationCryptoMiddlewareError.conversationNotInitialized)
    }
    
    func testDecryptionMaxSkipExceeded() throws {
        let userId = UserId()
        let conversationId = ConversationId()
        
        let header = Header(publicKey: "publicKey".bytes, numberOfMessagesInPreviousSendingChain: 10, messageNumber: 10)
        let message = Message(header: header, cipher: "ciphertext".bytes)
        let encryptedSecretKey = try JSONEncoder().encode(message)
        let encryptedMessage = "encryptedMessage".data
        
        let conversationStateBeforeDecryption = ConversationState(
            userId: userId,
            conversationId: conversationId,
            rootKey: "rootKey".data,
            rootChainPublicKey: "rootChainPublicKey".data,
            rootChainPrivateKey: "rootChainPrivateKey".data,
            rootChainRemotePublicKey: "rootChainRemotePublicKey".data,
            sendingChainKey: "sendingChainKey".data,
            receivingChainKey: "receivingChainKey".data,
            sendMessageNumber: 2,
            receivedMessageNumber: 2,
            previousSendingChainLength: 2
        )
        
        let expectedSessionStateBeforeDecryption = SessionState(
            rootKey: conversationStateBeforeDecryption.rootKey.keyExchangeKey,
            rootChainKeyPair: conversationStateBeforeDecryption.rootChainKeyPair.keyExchangeKeyPair,
            rootChainRemotePublicKey: conversationStateBeforeDecryption.rootChainRemotePublicKey?.keyExchangeKey,
            sendingChainKey: conversationStateBeforeDecryption.sendingChainKey?.keyExchangeKey,
            receivingChainKey: conversationStateBeforeDecryption.receivingChainKey?.keyExchangeKey,
            sendMessageNumber: conversationStateBeforeDecryption.sendMessageNumber,
            receivedMessageNumber: conversationStateBeforeDecryption.receivedMessageNumber,
            previousSendingChainLength: conversationStateBeforeDecryption.previousSendingChainLength,
            info: "info",
            maxSkip: 10
        )
        
        let messageKeyCache = MockMessageKeyCache()
        stub(cryptoStorageManager) { stub in
            when(stub.loadConversationState(userId: userId, conversationId: conversationId)).thenReturn(conversationStateBeforeDecryption)
            when(stub.messageKeyCache(conversationId: conversationId)).thenReturn(messageKeyCache)
        }
        
        stub(doubleRatchetProvider) { stub in
            when(stub.provideDoubleRatchet(sessionState: expectedSessionStateBeforeDecryption, messageKeyCache: any())).thenReturn(doubleRatchet)
        }
        
        stub(doubleRatchet) { stub in
            when(stub.setLogger(any())).thenDoNothing()
            when(stub.decrypt(message: message)).thenThrow(DRError.exceedMaxSkip)
        }
        
        XCTAssertThrowsSpecificError(_ = try conversationCryptoMiddleware.decrypt(encryptedData: encryptedMessage, encryptedSecretKey: encryptedSecretKey, from: userId, conversationId: conversationId), ConversationCryptoMiddlewareError.maxSkipExceeded)
        
        verify(cryptoStorageManager).loadConversationState(userId: userId, conversationId: conversationId)
        verify(doubleRatchetProvider).provideDoubleRatchet(sessionState: any(), messageKeyCache: any())
    }
    
    func testDecryptionDiscardedOldMessage() throws {
        let userId = UserId()
        let conversationId = ConversationId()
        
        let header = Header(publicKey: "publicKey".bytes, numberOfMessagesInPreviousSendingChain: 10, messageNumber: 10)
        let message = Message(header: header, cipher: "ciphertext".bytes)
        let encryptedSecretKey = try JSONEncoder().encode(message)
        let encryptedMessage = "encryptedMessage".data
        
        let conversationStateBeforeDecryption = ConversationState(
            userId: userId,
            conversationId: conversationId,
            rootKey: "rootKey".data,
            rootChainPublicKey: "rootChainPublicKey".data,
            rootChainPrivateKey: "rootChainPrivateKey".data,
            rootChainRemotePublicKey: "rootChainRemotePublicKey".data,
            sendingChainKey: "sendingChainKey".data,
            receivingChainKey: "receivingChainKey".data,
            sendMessageNumber: 2,
            receivedMessageNumber: 2,
            previousSendingChainLength: 2
        )
        
        let expectedSessionStateBeforeDecryption = SessionState(
            rootKey: conversationStateBeforeDecryption.rootKey.keyExchangeKey,
            rootChainKeyPair: conversationStateBeforeDecryption.rootChainKeyPair.keyExchangeKeyPair,
            rootChainRemotePublicKey: conversationStateBeforeDecryption.rootChainRemotePublicKey?.keyExchangeKey,
            sendingChainKey: conversationStateBeforeDecryption.sendingChainKey?.keyExchangeKey,
            receivingChainKey: conversationStateBeforeDecryption.receivingChainKey?.keyExchangeKey,
            sendMessageNumber: conversationStateBeforeDecryption.sendMessageNumber,
            receivedMessageNumber: conversationStateBeforeDecryption.receivedMessageNumber,
            previousSendingChainLength: conversationStateBeforeDecryption.previousSendingChainLength,
            info: "info",
            maxSkip: 10
        )
        
        let messageKeyCache = MockMessageKeyCache()
        stub(cryptoStorageManager) { stub in
            when(stub.loadConversationState(userId: userId, conversationId: conversationId)).thenReturn(conversationStateBeforeDecryption)
            when(stub.messageKeyCache(conversationId: conversationId)).thenReturn(messageKeyCache)
        }
        
        stub(doubleRatchetProvider) { stub in
            when(stub.provideDoubleRatchet(sessionState: expectedSessionStateBeforeDecryption, messageKeyCache: any())).thenReturn(doubleRatchet)
        }
        
        stub(doubleRatchet) { stub in
            when(stub.setLogger(any())).thenDoNothing()
            when(stub.decrypt(message: message)).thenThrow(DRError.discardOldMessage)
        }
        
        XCTAssertThrowsSpecificError(_ = try conversationCryptoMiddleware.decrypt(encryptedData: encryptedMessage, encryptedSecretKey: encryptedSecretKey, from: userId, conversationId: conversationId), ConversationCryptoMiddlewareError.discardedObsoleteMessage)
        
        verify(cryptoStorageManager).loadConversationState(userId: userId, conversationId: conversationId)
        verify(doubleRatchetProvider).provideDoubleRatchet(sessionState: any(), messageKeyCache: any())
    }
    
    func testDecryptionDecryptionError() throws {
        let userId = UserId()
        let conversationId = ConversationId()
        
        let header = Header(publicKey: "publicKey".bytes, numberOfMessagesInPreviousSendingChain: 10, messageNumber: 10)
        let message = Message(header: header, cipher: "ciphertext".bytes)
        let encryptedSecretKey = try JSONEncoder().encode(message)
        let encryptedMessage = "encryptedMessage".data
        
        let conversationStateBeforeDecryption = ConversationState(
            userId: userId,
            conversationId: conversationId,
            rootKey: "rootKey".data,
            rootChainPublicKey: "rootChainPublicKey".data,
            rootChainPrivateKey: "rootChainPrivateKey".data,
            rootChainRemotePublicKey: "rootChainRemotePublicKey".data,
            sendingChainKey: "sendingChainKey".data,
            receivingChainKey: "receivingChainKey".data,
            sendMessageNumber: 2,
            receivedMessageNumber: 2,
            previousSendingChainLength: 2
        )
        
        let expectedSessionStateBeforeDecryption = SessionState(
            rootKey: conversationStateBeforeDecryption.rootKey.keyExchangeKey,
            rootChainKeyPair: conversationStateBeforeDecryption.rootChainKeyPair.keyExchangeKeyPair,
            rootChainRemotePublicKey: conversationStateBeforeDecryption.rootChainRemotePublicKey?.keyExchangeKey,
            sendingChainKey: conversationStateBeforeDecryption.sendingChainKey?.keyExchangeKey,
            receivingChainKey: conversationStateBeforeDecryption.receivingChainKey?.keyExchangeKey,
            sendMessageNumber: conversationStateBeforeDecryption.sendMessageNumber,
            receivedMessageNumber: conversationStateBeforeDecryption.receivedMessageNumber,
            previousSendingChainLength: conversationStateBeforeDecryption.previousSendingChainLength,
            info: "info",
            maxSkip: 10
        )
        
        let messageKeyCache = MockMessageKeyCache()
        stub(cryptoStorageManager) { stub in
            when(stub.loadConversationState(userId: userId, conversationId: conversationId)).thenReturn(conversationStateBeforeDecryption)
            when(stub.messageKeyCache(conversationId: conversationId)).thenReturn(messageKeyCache)
        }
        
        stub(doubleRatchetProvider) { stub in
            when(stub.provideDoubleRatchet(sessionState: expectedSessionStateBeforeDecryption, messageKeyCache: any())).thenReturn(doubleRatchet)
        }
        
        stub(doubleRatchet) { stub in
            when(stub.setLogger(any())).thenDoNothing()
            when(stub.decrypt(message: message)).thenThrow(DRError.decryptionFailed)
        }
        
        XCTAssertThrowsSpecificError(_ = try conversationCryptoMiddleware.decrypt(encryptedData: encryptedMessage, encryptedSecretKey: encryptedSecretKey, from: userId, conversationId: conversationId), ConversationCryptoMiddlewareError.decryptionError)
        
        verify(cryptoStorageManager).loadConversationState(userId: userId, conversationId: conversationId)
        verify(doubleRatchetProvider).provideDoubleRatchet(sessionState: any(), messageKeyCache: any())
    }
}
