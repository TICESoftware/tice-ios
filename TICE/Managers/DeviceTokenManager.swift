//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import TICEAPIModels
import PromiseKit

enum DeviceTokenManagerError: LocalizedError {
    case tokenNotFound

    var errorDescription: String? {
        switch self {
        case .tokenNotFound: return "No device token found."
        }
    }
}

struct DeviceVerification {
    var deviceToken: Data
    var verificationCode: String
}

class DeviceTokenManager: DeviceTokenManagerType {
    let signedInUserManager: SignedInUserManagerType
    weak var postOffice: PostOfficeType?
    let backend: TICEAPI
    let notifier: Notifier

    var lastDeviceToken: Data?
    var verificationSeal: Resolver<String>?

    init(signedInUserManager: SignedInUserManagerType, postOffice: PostOfficeType, backend: TICEAPI, notifier: Notifier) {
        self.signedInUserManager = signedInUserManager
        self.postOffice = postOffice
        self.backend = backend
        self.notifier = notifier
    }

    deinit {
        postOffice?.handlers[.verificationMessageV1] = nil
    }

    func registerHandler() {
        postOffice?.handlers[.verificationMessageV1] = { [unowned self] payload, _, completion in
            guard let verificationMessage = payload as? VerificationMessage else {
                logger.error("Invalid payload. Expected verification message.")
                completion?(.failed)
                return
            }
            self.handleVerification(verificationCode: verificationMessage.verificationCode, completion: completion)
        }
    }
    
    func registerDevice(remoteNotificationsRegistry: RemoteNotificationsRegistry, forceRefresh: Bool) -> Promise<DeviceVerification> {
        firstly {
            requestDeviceToken(remoteNotificationsRegistry: remoteNotificationsRegistry, forceRefresh: forceRefresh)
        }.then { deviceToken in
            firstly {
                self.requestVerification(deviceToken: deviceToken)
            }.then { verificationCode in
                self.updateUser(deviceToken: deviceToken, verificationCode: verificationCode).map { verificationCode }
            }.map { verificationCode in
                return DeviceVerification(deviceToken: deviceToken, verificationCode: verificationCode)
            }
        }
    }
    
    func processDeviceToken(_ token: Data) {
        lastDeviceToken = token
        
        deviceTokenSeal?.fulfill(token)
        deviceTokenSeal = nil
    }

    private func handleVerification(verificationCode: String, completion: PostOfficeType.PayloadHandler?) {
        logger.info("Received verification code.")
        
        guard let verificationSeal = self.verificationSeal else { return }
        self.verificationSeal = nil
        
        verificationSeal.fulfill(verificationCode)
        completion?(.newData)
    }
    
    private func updateUser(deviceToken: Data, verificationCode: String) -> Promise<Void> {
        guard let signedInUser = signedInUserManager.signedInUser else {
            logger.debug("Not sending user update with new device token to backend because the user is not signed in.")
            return .value
        }

        return backend.updateUser(userId: signedInUser.userId, publicKeys: nil, deviceId: deviceToken, verificationCode: verificationCode, publicName: signedInUser.publicName)
    }

    private var deviceTokenSeal: Resolver<Data>?
    
    private func requestDeviceToken(remoteNotificationsRegistry: RemoteNotificationsRegistry, forceRefresh: Bool) -> Promise<Data> {
        if forceRefresh {
            self.lastDeviceToken = nil
        }
        
        if let cachedDeviceToken = lastDeviceToken {
            return .value(cachedDeviceToken)
        }
        
        let (promise, seal) = Promise<Data>.pending()
        deviceTokenSeal = seal
        remoteNotificationsRegistry.registerForRemoteNotifications()
        
        return promise
    }

    private func requestVerification(deviceToken: Data) -> Promise<String> {
        let (verificationPromise, verificationSeal) = Promise<String>.pending()
        self.verificationSeal = verificationSeal
        
        backend.verify(deviceId: deviceToken).catch { error in
            verificationSeal.reject(error)
        }
        
        return verificationPromise
    }
}
