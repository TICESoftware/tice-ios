//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import PromiseKit
import TICEAPIModels

class TooFewOneTimePrekeysHandler: TooFewOneTimePrekeysHandlerType {

    let conversationCryptoMiddleware: ConversationCryptoMiddlewareType
    let backend: TICEAPI
    let signedInUser: SignedInUser

    weak var postOffice: PostOfficeType?

    init(conversationCryptoMiddleware: ConversationCryptoMiddlewareType, backend: TICEAPI, signedInUser: SignedInUser, postOffice: PostOfficeType) {
        self.conversationCryptoMiddleware = conversationCryptoMiddleware
        self.backend = backend
        self.signedInUser = signedInUser
        self.postOffice = postOffice
    }

    func registerHandler() {
        postOffice?.handlers[.fewOneTimePrekeysV1] = { [unowned self] in
            handleFewOneTimePrekeys(payload: $0, metaInfo: $1, completion: $2)
        }
    }

    deinit {
        postOffice?.handlers[.fewOneTimePrekeysV1] = nil
    }

    func handleFewOneTimePrekeys(payload: Payload, metaInfo: PayloadMetaInfo, completion: PostOfficeType.PayloadHandler?) {
        logger.info("The server says it's running low on one-time prekeys. Renewing public handshake key material.")

        firstly { () -> Promise<Void> in
            let userPublicKeys = try conversationCryptoMiddleware.renewHandshakeKeyMaterial(privateSigningKey: signedInUser.privateSigningKey)
            return backend.updateUser(userId: signedInUser.userId, publicKeys: userPublicKeys, deviceId: nil, verificationCode: nil, publicName: signedInUser.publicName)
        }.done {
            completion?(.newData)
        }.catch { error in
            logger.error(error)
            completion?(.failed)
        }
    }
}
