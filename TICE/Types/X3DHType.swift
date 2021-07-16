//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import Sodium
import X3DH

protocol X3DHType {
    func generateIdentityKeyPair() throws -> KeyExchange.KeyPair
    func generateSignedPrekeyPair(signer: @escaping PrekeySigner) throws -> X3DH.SignedPrekeyPair
    func generateOneTimePrekeyPairs(count: Int) throws -> [KeyExchange.KeyPair]
    
    func initiateKeyAgreement(remoteIdentityKey: KeyExchange.PublicKey, remotePrekey: KeyExchange.PublicKey, prekeySignature: Data, remoteOneTimePrekey: KeyExchange.PublicKey?, identityKeyPair: KeyExchange.KeyPair, prekey: KeyExchange.PublicKey, prekeySignatureVerifier: @escaping PrekeySignatureVerifier, info: String) throws -> X3DH.KeyAgreementInitiation
    func sharedSecretFromKeyAgreement(remoteIdentityKey: KeyExchange.PublicKey, remoteEphemeralKey: KeyExchange.PublicKey, usedOneTimePrekeyPair: KeyExchange.KeyPair?, identityKeyPair: KeyExchange.KeyPair, prekeyPair: KeyExchange.KeyPair, info: String) throws -> Bytes
}

extension X3DH: X3DHType { }
