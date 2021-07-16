//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import PromiseKit

extension Promise {
    func timeout(seconds: TimeInterval, thrower: @escaping () throws -> Never) -> Promise<T> {
        let pending = Promise<T>.pending()
        after(seconds: seconds).done {
            try thrower()
        }.catch { error in
            pending.resolver.reject(error)
        }
        pipe(to: pending.resolver.resolve)
        return pending.promise
    }
}
