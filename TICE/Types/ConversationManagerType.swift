//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import PromiseKit
import TICEAPIModels

protocol ConversationManagerType {
    var delegate: ConversationManagerDelegate? { get set }

    func initConversation(userId: UserId, collapsing: Bool) -> Promise<Void>
    func isConversationInitialized(userId: UserId, collapsing: Bool) -> Bool
    func conversationInvitation(userId: UserId, collapsing: Bool) -> ConversationInvitation?
    func encrypt(data: Data, for userId: UserId, collapsing: Bool) -> Promise<Ciphertext>

    func registerHandler()
}
