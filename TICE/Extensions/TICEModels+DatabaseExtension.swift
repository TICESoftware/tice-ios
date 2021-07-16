//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import GRDB
import TICEAPIModels

extension Membership: PersistableRecord, FetchableRecord, TableRecord { }
extension User: PersistableRecord, FetchableRecord { }
extension ConversationState: PersistableRecord, FetchableRecord, TableRecord { }
