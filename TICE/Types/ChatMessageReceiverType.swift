//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels

protocol ChatMessageReceiverType {
    func registerHandler()
    func handleChatMessage(payload: Payload, metaInfo: PayloadMetaInfo, completion: PostOfficeType.PayloadHandler?)
}
