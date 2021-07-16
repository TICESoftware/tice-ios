//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels

protocol ConversationStorageManagerType: DeletableStorageManagerType {
    func storeOutboundConversationInvitation(receiverId: UserId, conversationId: ConversationId, conversationInvitation: ConversationInvitation) throws
    func outboundConversationInvitation(receiverId: UserId, conversationId: ConversationId) throws -> ConversationInvitation?
    func deleteOutboundConversationInvitation(receiverId: UserId, conversationId: ConversationId) throws

    func storeInboundConversationInvitation(senderId: UserId, conversationId: ConversationId, conversationInvitation: ConversationInvitation, timestamp: Date) throws
    func inboundConversationInvitation(senderId: UserId, conversationId: ConversationId) throws -> InboundConversationInvitation?
    
    func storeReceivedReset(senderId: UserId, conversationId: ConversationId, timestamp: Date) throws
    func receivedReset(senderId: UserId, conversationId: ConversationId) throws -> Date?

    func storeInvalidConversation(userId: UserId, conversationId: ConversationId, fingerprint: ConversationFingerprint, timestamp: Date, resendResetTimeout: Date) throws
    func invalidConversation(userId: UserId, conversationId: ConversationId) throws -> InvalidConversation?
    func updateInvalidConversation(userId: UserId, conversationId: ConversationId, resendResetTimeout: Date) throws
}
