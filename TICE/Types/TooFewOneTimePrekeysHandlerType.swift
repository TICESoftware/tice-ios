//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels

protocol TooFewOneTimePrekeysHandlerType {
    func registerHandler()
    func handleFewOneTimePrekeys(payload: Payload, metaInfo: PayloadMetaInfo, completion: PostOfficeType.PayloadHandler?)
}
