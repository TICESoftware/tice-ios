//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels
import enum UIKit.UIBackgroundFetchResult

protocol Receiver {
    var delegate: EnvelopeReceiverDelegate? { get }
    
    func receive(envelope: Envelope)
    func receive(envelope: Envelope, timeout: TimeInterval?, completionHandler: ((ReceiveEnvelopeResult) -> Void)?)
}

extension Receiver {
    func receive(envelope: Envelope) {
        delegate?.receive(envelope: envelope)
    }
    
    func receive(envelope: Envelope, timeout: TimeInterval?, completionHandler: ((ReceiveEnvelopeResult) -> Void)?) {
        delegate?.receive(envelope: envelope, timeout: timeout, completionHandler: completionHandler)
    }
}

protocol EnvelopeReceiverDelegate: AnyObject {
    func receive(envelope: Envelope)
    func receive(envelope: Envelope, timeout: TimeInterval?, completionHandler: ((ReceiveEnvelopeResult) -> Void)?)
}

public enum ReceiveEnvelopeResult: String {
    case duplicate
    case noData
    case newData
    case failed
    case timeOut
    
    init(result: UIBackgroundFetchResult) {
        switch result {
        case .noData:
            self = .noData
        case .newData:
            self = .newData
        case .failed:
            self = .failed
        @unknown default:
            logger.error("Unexpected background fetch result type.")
            fatalError()
        }
    }
    
    var rawResult: UIBackgroundFetchResult {
        switch self {
        case .duplicate:
            return .noData
        case .noData:
            return .noData
        case .newData:
            return .newData
        case .failed:
            return .failed
        case .timeOut:
            return .noData
        }
    }
}
