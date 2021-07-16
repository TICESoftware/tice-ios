//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import PromiseKit
import TICEAPIModels

protocol MailboxType {
    func send(payloadContainer: PayloadContainer, to members: [Membership], serverSignedMembershipCertificate: Certificate, priority: MessagePriority, collapseId: Envelope.CollapseIdentifier?) -> Promise<Void>
}
