//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import PromiseKit
import TICEAPIModels

protocol TeamBroadcaster: AnyObject {
    func sendToAllTeams(payloadContainer: PayloadContainer) -> Promise<Void>
}
