//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import UIKit
import Shouter

public class ShakeDetectingWindow: UIWindow {
    override public func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            Shouter.default.notify(DidShakeDeviceObserver.self) {
                $0.didShakeDevice(motion: motion, event: event)
            }
            return
        }

        super.motionEnded(motion, with: event)
    }
}

protocol DidShakeDeviceObserver {
    func didShakeDevice(motion: UIEvent.EventSubtype, event: UIEvent?)
}
