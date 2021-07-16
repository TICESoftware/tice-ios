//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import PromiseKit

protocol DeviceTokenManagerType {
    func registerHandler()
    
    func registerDevice(remoteNotificationsRegistry: RemoteNotificationsRegistry, forceRefresh: Bool) -> Promise<DeviceVerification>
    func processDeviceToken(_ deviceToken: Data)
}
