//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels
import PromiseKit

protocol ConversationManagerDelegate: AnyObject {
    func sendResetReply(to userId: UserId, receiverCertificate: Certificate, senderCertificate: Certificate, collapseId: Envelope.CollapseIdentifier?) -> Promise<Void>
}
