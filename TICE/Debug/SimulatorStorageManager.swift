//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import PromiseKit

class SimulatorDeviceTokenManager: DeviceTokenManagerType {
    
    private var deviceToken = Data()
    
    func registerHandler() {
    }

    func registerDevice(remoteNotificationsRegistry: RemoteNotificationsRegistry, forceRefresh: Bool) -> Promise<DeviceVerification> {
        return .value(DeviceVerification(deviceToken: deviceToken, verificationCode: "SIM-IOS"))
    }

    func processDeviceToken(_ token: Data) {
    }
}
