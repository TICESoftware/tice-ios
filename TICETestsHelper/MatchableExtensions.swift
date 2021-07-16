//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import Cuckoo
import CoreLocation
import TICEAPIModels
import Version
import UserNotifications
import Sodium
import DoubleRatchet

@testable import TICE

extension UUID: Matchable { }
extension Meetup: Matchable {
    public var matcher: ParameterMatcher<Meetup> {
        return ParameterMatcher { $0.groupId == self.groupId }
    }
}
extension Team: Matchable {
    public var matcher: ParameterMatcher<Team> {
        return ParameterMatcher { $0.groupId == self.groupId }
    }
}
extension Membership: Matchable {
    public var matcher: ParameterMatcher<Membership> {
        return ParameterMatcher { $0 == self }
    }
}
extension CLLocation: Matchable { }
extension Location: OptionalMatchable {
    public typealias OptionalMatchedType = Location

    public var optionalMatcher: ParameterMatcher<Location?> {
        return ParameterMatcher { $0?.latitude == self.latitude && $0?.longitude == self.longitude }
    }
}
extension LocationManager: OptionalMatchable { }
extension Data: Matchable { }
extension Data: OptionalMatchable { }
extension Date: Matchable { }
extension User: Matchable { }
extension GroupType: Matchable { }
extension JoinMode: Matchable { }
extension PermissionMode: Matchable { }
extension ParentGroup: OptionalMatchable { }
extension NotificationRecipient: Matchable { }
extension PayloadContainer: Matchable {
    public var matcher: ParameterMatcher<PayloadContainer> {
        return ParameterMatcher { $0.payloadType == self.payloadType }
    }
}
extension ConversationInvitation: Matchable { }
extension GroupUpdate.Action: Matchable { }
extension MessagePriority: Matchable { }
extension AppState: OptionalMatchable { }
extension Version: Matchable { }
extension UserPublicKeys: OptionalMatchable { }
extension Recipient: Matchable { }
extension Envelope: Matchable {
    public var matcher: ParameterMatcher<Envelope> {
        ParameterMatcher { $0.id == self.id }
    }
}
extension EnvelopeCacheRecord.ProcessingState: Matchable { }
extension UNAuthorizationOptions: Matchable { }
extension AppState: Matchable { }
extension TICE.KeyPair: Matchable {
    public var matcher: ParameterMatcher<TICE.KeyPair> {
        ParameterMatcher { $0.publicKey == self.publicKey && $0.privateKey == self.privateKey }
    }
}
extension KeyExchange.KeyPair: Matchable {
    public var matcher: ParameterMatcher<KeyExchange.KeyPair> {
        ParameterMatcher { $0.publicKey == self.publicKey && $0.secretKey == self.secretKey }
    }
}
extension KeyExchange.KeyPair: OptionalMatchable {
    public var optionalMatcher: ParameterMatcher<KeyExchange.KeyPair?> {
        ParameterMatcher { $0?.publicKey == self.publicKey && $0?.secretKey == self.secretKey }
    }
}
extension KeyExchange.PublicKey: OptionalMatchable {
    public var optionalMatcher: ParameterMatcher<KeyExchange.PublicKey?> {
        ParameterMatcher { $0 == self }
    }
}
extension MockMessageKeyCache: OptionalMatchable { }
extension ConversationState: Matchable { }
extension SessionState: Matchable {
    public var matcher: ParameterMatcher<SessionState> {
        ParameterMatcher {
            $0.rootKey == self.rootKey &&
                $0.rootChainKeyPair.publicKey == self.rootChainKeyPair.publicKey &&
                $0.rootChainKeyPair.secretKey == self.rootChainKeyPair.secretKey &&
                $0.rootChainRemotePublicKey == self.rootChainRemotePublicKey &&
                $0.sendingChainKey == self.sendingChainKey &&
                $0.receivingChainKey == self.receivingChainKey &&
                $0.sendMessageNumber == self.sendMessageNumber &&
                $0.receivedMessageNumber == self.receivedMessageNumber &&
                $0.previousSendingChainLength == self.previousSendingChainLength &&
                $0.info == self.info &&
                $0.maxSkip == self.maxSkip
        }
    }
}
extension Message: Matchable {
    public var matcher: ParameterMatcher<Message> {
        ParameterMatcher {
            $0.header.publicKey == self.header.publicKey &&
                $0.header.messageNumber == self.header.messageNumber &&
                $0.header.numberOfMessagesInPreviousSendingChain == self.header.numberOfMessagesInPreviousSendingChain &&
                $0.cipher == self.cipher
        }
    }
}
