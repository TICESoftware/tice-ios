//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import TICEAPIModels
import GRDB

struct EnvelopeCacheRecord: Codable, PersistableRecord, FetchableRecord, TableRecord {
    let id: MessageId
    let senderId: UserId
    var state: ProcessingState
    let timestamp: Date

    enum ProcessingState: Int, Codable {
        case seen = 0
        case handling = 1
        case handled = 2
    }
}

class PostOfficeStorageManager: PostOfficeStorageManagerType {

    enum StorageKey: String {
        case messageCache
    }

    let database: DatabaseWriter

    init(database: DatabaseWriter) {
        self.database = database
    }

    func updateCacheRecord(for envelope: Envelope, state: EnvelopeCacheRecord.ProcessingState) {
        let type = envelope.payloadContainer.payloadType
        guard type != .verificationMessageV1,
            type != .fewOneTimePrekeysV1 else { return }
        let record = EnvelopeCacheRecord(id: envelope.id, senderId: envelope.senderId, state: state, timestamp: envelope.timestamp)

        do {
            try database.write { db in
                try record.save(db)
            }
        } catch {
            logger.error("Failed to update envelope cache record: \(String(describing: error))")
        }
    }

    func isCached(envelope: Envelope) -> Bool {
        do {
            return try database.read { db in
                try EnvelopeCacheRecord.fetchOne(db, key: ["id": envelope.id, "senderId": envelope.senderId]) != nil
            }
        } catch {
            logger.error("Failed to fetch envelope cache record: \(String(describing: error))")
            return false
        }
    }

    func deleteCacheRecordsOlderThan(_ date: Date) throws {
        return try database.write { db in
            try EnvelopeCacheRecord
                .filter(Column("timestamp") < date)
                .deleteAll(db)
        }
    }
}

extension PostOfficeStorageManager: DeletableStorageManagerType {
    func deleteAllData() {
        do {
            try database.write { try $0.drop(table: EnvelopeCacheRecord.databaseTableName) }
        } catch {
            logger.error("Error during deletion of all post office data: \(String(describing: error))")
        }
    }
}
