//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import os
import GRDB
import Sniffer
import ZIPFoundation
import Logging

#if DEBUG
let logger = TICELogger(logLevel: .trace, logHistoryLimit: Config.logHistoryLimit)
#elseif TESTING || PREVIEW
let logger = TICELogger(logLevel: .debug, logHistoryLimit: Config.logHistoryLimit)
#else
let logger = TICELogger(logLevel: .debug, logHistoryLimit: Config.logHistoryLimit)
#endif

enum LoggerError: LocalizedError {
    case dataGenerationFailed
}

class TICELogger {
    var logLevel: LogLevel
    private var database: DatabaseWriter
    private let logHistoryLimit: TimeInterval
    private let osLog = OSLog(subsystem: Bundle.main.appBundleId, category: Config.logIdentifier)
    
    private var storageAttached: Bool
    
    lazy var swiftLogger: Logging.Logger = {
        Logger(label: Config.logIdentifier) { TICELogHandler(identifier: $0, logLevel: logLevel.swiftLogLevel, logger: self) }
    }()
    
    let headerExcludes = [
        "X-Authorization",
        "X-ServerSignedMembershipCertificate"
    ]
    
    let bodyExcludesSingleValues = [
        "encryptedSettings",
        "encryptedInternalSettings",
        "selfSignedAdminCertificate",
        "selfSignedMembershipCertificate",
        "serverSignedMembershipCertificate",
        "serverSignedAdminCertificate",
        "receiverServerSignedMembershipCertificate",
        "senderServerSignedMembershipCertificate",
        "publicSigningKey",
        "signingKey",
        "identityKey",
        "prekeySignature",
        "signedPrekey",
        "encryptedMembership",
        "groupTag",
        "newTokenKey",
        "parentEncryptedGroupKey",
        "oneTimePrekey",
        "encryptedMessageKey",
        "ephemeralKey",
        "usedOneTimePrekey",
        "encryptedMessage",
        "ciphertext",
        "encryptedKey"
    ]
    
    let bodyExcludesCollections = [
        "oneTimePrekeys",
        "encryptedMemberships"
    ]
    
    init(logLevel: LogLevel, database: DatabaseWriter? = nil, logHistoryLimit: TimeInterval) {
        self.logLevel = logLevel
        
        if let database = database {
            self.database = database
            self.storageAttached = true
        } else {
            self.database = DatabaseQueue()
            self.storageAttached = false
        }
        
        self.logHistoryLimit = logHistoryLimit
        
        do {
            try self.database.write { db in
                try db.create(table: Log.databaseTableName, ifNotExists: true) { t in
                    t.autoIncrementedPrimaryKey("id")
                    t.column("timestamp", .blob).notNull()
                    t.column("level", .integer).notNull()
                    t.column("process", .text).notNull()
                    t.column("message", .text).notNull()
                    t.column("file", .text).notNull()
                    t.column("function", .text).notNull()
                    t.column("line", .integer).notNull()
                }
            }
        } catch {
            fatalError("Log database setup failed.")
        }
        
        debug("Logger initialized.")
        
        info("Process: \(ProcessInfo.processInfo.processName)")
        info("Environment: \(Bundle.main.environment)")
        info("Version: \(Bundle.main.appVersion)")
        info("Revision: \(Bundle.main.appRevision)\(Bundle.main.appRevisionDirty ? "*" : "")")
    }
    
    func attachNetworkSniffer(urlSessionConfiguration: URLSessionConfiguration? = nil) {
        Sniffer.register()
    
        if let configuration = urlSessionConfiguration {
            Sniffer.enable(in: configuration)
        }
        
        Sniffer.ignore(domains: ["beekeeper.tice.app"])
        Sniffer.onLogger = { _, _, log in
            logger.trace("Network event\n" + self.cropNetworkLog(log))
        }
    }
    
    func attachStorage(database newDatabase: DatabaseWriter) throws {
        guard !storageAttached else {
            logger.info("Storage has already been attached before.")
            return
        }
        
        let logs = try database.read { try Log.fetchAll($0) }
        
        database = newDatabase
        
        try database.write { db in
            try logs.forEach {
                print("Transferring log entry.")
                try $0.save(db)
            }
        }
        
        storageAttached = true
    }
    
    func getLogs(logLevel: LogLevel, since startDate: Date? = nil) throws -> [Log] {
        return try database.read {
            var filteredLogs = Log.filter(Column("level") >= logLevel)
                
            if let startDate = startDate {
                filteredLogs = filteredLogs.filter(Column("timestamp") >= startDate)
            }
            
            return try filteredLogs.fetchAll($0)
        }
    }
    
    func generateLogData(logLevel: LogLevel, since startDate: Date? = nil) throws -> Data {
        let logString = try getLogs(logLevel: logLevel, since: startDate).reduce("") { $0 + "\n" + String(describing: $1) }
        
        guard let logData = logString.data(using: .utf8) else {
            throw LoggerError.dataGenerationFailed
        }
        
        return logData
    }
    
    func generateCompressedLogData(logLevel: LogLevel, since startDate: Date? = nil) throws -> Data {
        let logData = try generateLogData(logLevel: logLevel, since: startDate)
        
        let fileManager = FileManager.default
        let fileURLWithoutExtension = fileManager.temporaryDirectory.appendingPathComponent("logs_\(Bundle.main.verboseVersionString)")
        let sourceFileURL = fileURLWithoutExtension.appendingPathExtension("log")
        let destinationFileURL = fileURLWithoutExtension.appendingPathExtension("zip")
        
        if fileManager.fileExists(atPath: destinationFileURL.path) {
            try fileManager.removeItem(at: destinationFileURL)
        }
        
        try logData.write(to: sourceFileURL)
        try fileManager.zipItem(at: sourceFileURL, to: destinationFileURL)
        
        return try Data(contentsOf: destinationFileURL)
    }
    
    func observeLogs(observer: @escaping (([Log]) -> Void)) throws -> ObserverToken {
        ValueObservation.tracking(Log.fetchAll).start(in: database, onError: { self.error($0) }, onChange: observer)
    }
    
    func deleteAllLogs() throws {
        return try database.write { try Log.deleteAll($0) }
    }
    
    func log(level: LogLevel, message: String, file: String, line: UInt, function: String) {
        guard level >= logLevel else {
            return
        }
        
        guard let fileName = file.components(separatedBy: "/").last else {
            os_log(OSLogType.error, log: osLog, "Called log from unexpected file: %{public}s", file)
            return
        }
        
        let processName = ProcessInfo.processInfo.processName
        guard let process = Process(processName: processName) else {
            os_log(OSLogType.error, log: osLog, "Unexpected process name: %{public}s", processName)
            return
        }
        
        os_log(level.osLogLevel, log: osLog, "%{public}s %{public}s %{public}s @ %{public}s:%u - %{public}s", level.stringValue, process.rawValue, fileName, function, line, message)
        
        #if DEBUG
        guard level > .trace else { return }
        #endif
        
        let log = Log(timestamp: Date(), level: level, process: process, message: message.description, file: fileName, function: function, line: line)
        
        do {
            try database.write { try log.save($0) }
        } catch {
            os_log(OSLogType.error, log: osLog, "Failed to save log to database: %@", error.localizedDescription)
        }
    }
    
    func cleanUp() throws {
        let threshold = Date().addingTimeInterval(-1 * logHistoryLimit)
        let deletedLogs = try database.write { db in
            try Log
                .filter(Column("timestamp") < threshold)
                .deleteAll(db)
        }
        
        debug("Deleted \(deletedLogs) logs.")
    }
    
    private func cropNetworkLog(_ log: String) -> String {
        var string = log
        
        // Crop fetched messages
        string = string.replacingOccurrences(of: #""messages"(.|\n)*(?=\}\n\])"#, with: "[Cropped messages]", options: .regularExpression)
        
        // Crop header fields
        for headerField in headerExcludes {
            string = string.replacingOccurrences(of: #"\b\#(headerField) : .*"#, with: "[Cropped \(headerField) Header]", options: .regularExpression)
        }
        
        // Crop body fields
        for bodyField in bodyExcludesCollections {
            string = string.replacingOccurrences(of: #"\"\#(bodyField)[^\]]*\]"#, with: "[Cropped \(bodyField)]", options: .regularExpression)
        }
        
        for bodyField in bodyExcludesSingleValues {
            string = string.replacingOccurrences(of: #"(\")?\#(bodyField).*"#, with: "[Cropped \(bodyField)]", options: .regularExpression)
        }
        
        return string
    }

    func trace(_ message: String, file: String = #file, line: UInt = #line, function: String = #function) {
        log(level: .trace, message: message, file: file, line: line, function: function)
    }
    
    func debug(_ message: String, file: String = #file, line: UInt = #line, function: String = #function) {
        log(level: .debug, message: message, file: file, line: line, function: function)
    }
    
    func info(_ message: String, file: String = #file, line: UInt = #line, function: String = #function) {
        log(level: .info, message: message, file: file, line: line, function: function)
    }
    
    func warning(_ message: String, file: String = #file, line: UInt = #line, function: String = #function) {
        log(level: .warning, message: message, file: file, line: line, function: function)
    }
    
    func error(_ message: String, file: String = #file, line: UInt = #line, function: String = #function) {
        log(level: .error, message: message, file: file, line: line, function: function)
    }
    
    func error(_ error: Error, file: String = #file, line: UInt = #line, function: String = #function) {
        log(level: .error, message: error.localizedDescription, file: file, line: line, function: function)
    }
}

struct Log: Codable, PersistableRecord, FetchableRecord, CustomStringConvertible {
    let timestamp: Date
    let level: LogLevel
    let process: Process
    let message: String
    let file: String
    let function: String
    let line: UInt
    
    var description: String {
        "\(timestamp) \(process.rawValue) \(level.stringValue) \(file) @ \(function):\(line) - \(message)"
    }
}

enum Process: String, Codable {
    case app = "APP"
    case notificationServiceExtension = "NSE"
    
    init?(processName: String) {
        switch processName {
        case "TICE": self = .app
        case "NotificationServiceExtension": self = .notificationServiceExtension
        default: return nil
        }
    }
}

enum LogLevel: Int, RawRepresentable, Codable, Comparable, DatabaseValueConvertible {
    case trace
    case debug
    case info
    case warning
    case error
    
    init(swiftLogLevel: Logging.Logger.Level) {
        switch swiftLogLevel {
        case .trace: self = .trace
        case .debug: self = .debug
        case .info, .notice: self = .info
        case .warning: self = .warning
        case .error, .critical: self = .error
        }
    }

    var osLogLevel: OSLogType {
        switch self {
        case .error: return .error
        case .warning: return .default
        case .info: return .info
        case .debug, .trace: return .debug

        }
    }
    
    var swiftLogLevel: Logging.Logger.Level {
        switch self {
        case .trace: return .trace
        case .debug: return .debug
        case .info: return .info
        case .warning: return .warning
        case .error: return .error
        }
    }

    var stringValue: String {
        switch self {
        case .trace: return "⚪️"
        case .debug: return "🔵"
        case .info: return "🟢"
        case .warning: return "🟡"
        case .error: return "🔴"
        }
    }

    // Synthesized in Swift 5.3
    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct TICELogHandler: LogHandler {
    var metadata: Logging.Logger.Metadata = [:]
    var logLevel: Logging.Logger.Level
    let identifier: String
    let logger: TICELogger
    
    init(identifier: String, logLevel: Logging.Logger.Level, logger: TICELogger) {
        self.identifier = identifier
        self.logLevel = logLevel
        self.logger = logger
    }
    
    func log(level: Logging.Logger.Level, message: Logging.Logger.Message, metadata: Logging.Logger.Metadata?, file: String, function: String, line: UInt) {
        logger.log(level: LogLevel(swiftLogLevel: level), message: message.description, file: file, line: line, function: function)
    }
    
    subscript(metadataKey metadataKey: String) -> Logging.Logger.Metadata.Value? {
        get {
            metadata[metadataKey]
        }
        set(newValue) {
            metadata[metadataKey] = newValue
        }
    }
}
