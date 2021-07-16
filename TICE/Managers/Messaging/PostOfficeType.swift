//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels
import PromiseKit

protocol PostOfficeType: AnyObject {
    typealias PayloadHandler = (ReceiveEnvelopeResult) -> Void
    typealias Handler = (Payload, PayloadMetaInfo, PayloadHandler?) -> Void
    typealias DecodingStrategy = ((Payload, PayloadMetaInfo) throws -> PayloadContainerBundle)

    var handlers: [PayloadContainer.PayloadType: Handler] { get set }
    var decodingStrategies: [PayloadContainer.PayloadType: DecodingStrategy] { get set }
    var decodingSuccessInterceptor: ((PayloadContainerBundle) -> Void)? { get set }
    
    func fetchMessages() -> Promise<Void>
}
