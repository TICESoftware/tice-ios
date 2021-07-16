//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import GRDB

struct MockObserverToken: DatabaseCancellable {
    func cancel() { }
}
