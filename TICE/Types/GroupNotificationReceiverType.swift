//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels

protocol GroupNotificationReceiverType {
    func registerHandler()
    func handleGroupUpdate(payload: Payload, metaInfo: PayloadMetaInfo, completion: PostOfficeType.PayloadHandler?)
}
