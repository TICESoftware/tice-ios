//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation

protocol Notifier {
    func register<T>(_ type: T.Type, observer: T)
    func unregister<T>(_ type: T.Type, observer: T)
    func unregister<T>(_ type: T.Type)

    func notify<T>(_ type: T.Type, block: (T) -> Void)
}
