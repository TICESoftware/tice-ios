//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels
import enum UIKit.UIBackgroundFetchResult

public class PushReceiver: PushReceiverType {

    let decoder: JSONDecoder

    var timeout: TimeInterval
    
    weak var delegate: EnvelopeReceiverDelegate?

    init(decoder: JSONDecoder, timeout: TimeInterval) {
        self.decoder = decoder
        self.timeout = timeout
    }
    
    func didReceiveRemoteNotification(userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: ((UIBackgroundFetchResult) -> Void)?) {
        DispatchQueue.global(qos: .userInteractive).async {
            self.didReceiveRemoteNotificationSynchronous(userInfo: userInfo, fetchCompletionHandler: completionHandler)
        }
    }
    
    /**
     Handles incoming push notifications in a synchronous (blocking) way. Thus, this method should not be called on the main thread
     */
    private func didReceiveRemoteNotificationSynchronous(userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: ((UIBackgroundFetchResult) -> Void)?) {
        guard let payload = userInfo["payload"] as? [AnyHashable: Any] else {
            completionHandler?(.noData)
            return
        }
        
        do {
            let envelope = try Envelope(dictionary: payload, decoder: decoder)
            let timeout = Double(self.timeout)
            let date = Date()
            
            let queue = DispatchQueue(label: "serialQueue")
            var wasCalled = false
            let semaphore = DispatchSemaphore(value: 0)
            
            logger.info("Did receive envelope \(envelope.id) via push notification.")
            
            let wrappedHandler = { (result: ReceiveEnvelopeResult) in
                queue.sync {
                    guard !wasCalled else { return }
                    wasCalled = true
                    logger.info("Completion handler was called after \(-date.timeIntervalSinceNow)s for push notification (envelope \(envelope.id)) with result: \(result)")
                    completionHandler?(result.rawResult)
                    semaphore.signal()
                }
            }
            
            receive(envelope: envelope, timeout: timeout, completionHandler: wrappedHandler)
            
            let result = semaphore.wait(wallTimeout: .now() + .milliseconds(Int(timeout * 1000)))
            
            if result == .timedOut {
                wrappedHandler(.timeOut)
            }
        } catch {
            logger.error(error)
            completionHandler?(.failed)
        }
    }
}
