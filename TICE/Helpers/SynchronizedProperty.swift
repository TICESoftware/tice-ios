//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation

@propertyWrapper
public class SynchronizedProperty<T> {
    private let propertyQueue = DispatchQueue(label: "app.tice.TICE.synchronizedProperty", attributes: .concurrent)
    private var value: T

    public var wrappedValue: T {
        get { return propertyQueue.sync { value } }
        set { propertyQueue.async(flags: .barrier) { [weak self] in self?.value = newValue } }
    }

    public init(wrappedValue: T) {
        self.value = wrappedValue
    }
}
