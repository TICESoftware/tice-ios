//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels

protocol PostOfficeStorageManagerType: DeletableStorageManagerType {
    func updateCacheRecord(for envelope: Envelope, state: EnvelopeCacheRecord.ProcessingState)
    func isCached(envelope: Envelope) -> Bool
    func deleteCacheRecordsOlderThan(_ date: Date) throws
}
