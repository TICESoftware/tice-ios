//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation

enum ServerCertificateStorageManagerError: LocalizedError {
    case serverSigningKeyNotFound

    var errorDescription: String? {
        switch self {
        case .serverSigningKeyNotFound: return L10n.Error.ServerCertificateStorageManager.serverSigningKeyNotFound
        }
    }
}

protocol ServerCertificateStorageManagerType {
    func loadServerPublicSigningKey() throws -> PublicKey
}

class ServerCertificateStorageManager: ServerCertificateStorageManagerType {
    func loadServerPublicSigningKey() throws -> PublicKey {
        var fileName = "ServerSigningKey"
        
        #if DEVELOPMENT
        fileName += ".development"
        #elseif TESTING
        fileName += ".testing"
        #elseif PREVIEW
        fileName += ".preview"
        #else
        fileName += ".production"
        #endif
        
        guard let file = Bundle.main.path(forResource: fileName, ofType: "pem"),
            let rawValue = try? String(contentsOfFile: file) else {
                throw ServerCertificateStorageManagerError.serverSigningKeyNotFound
        }
        return PublicKey(rawValue.bytes)
    }
}
