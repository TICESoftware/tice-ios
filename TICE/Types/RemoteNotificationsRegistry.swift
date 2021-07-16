//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit

protocol RemoteNotificationsRegistry {
    func registerForRemoteNotifications()
}

extension UIApplication: RemoteNotificationsRegistry { }
