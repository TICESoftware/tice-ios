//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import GRDB

typealias ObserverToken = DatabaseCancellable

extension DatabaseReader {
    static func logError(error: Error) {
        logger.error("Error during observation: \(error)")
    }
    
    func observe<Value>(_ fetch: @escaping (Database) throws -> Value, queue: DispatchQueue, onChange: @escaping (Value) -> Void, onError: @escaping (Error) -> Void = logError) -> ObserverToken {
        return ValueObservation
            .tracking(fetch)
            .start(
                in: self,
                scheduling: .async(onQueue: queue),
                onError: onError,
                onChange: onChange
            )
    }
}
