//
//  Logger.swift
//  YabaiIndicator
//
//  Created for debugging and crash analysis
//

import Foundation
import os.log

/// Thread-safe file-based logger with crash capture capabilities
class Logger {
    static let shared = Logger()

    private let logQueue = DispatchQueue(label: "com.yabaiindicator.logger", qos: .utility)
    private var fileHandle: FileHandle?
    private let dateFormatter: DateFormatter
    private let logFileURL: URL
    private let maxLogSize: Int = 10 * 1024 * 1024  // 10MB max log size
    private var lastFlushTime: Date = Date()
    private let flushInterval: TimeInterval = 5.0  // Flush every 5 seconds

    // Statistics
    private var stats = LogStats()

    struct LogStats {
        var refreshCount: Int = 0
        var spaceChangeCount: Int = 0
        var displayChangeCount: Int = 0
        var socketMessageCount: Int = 0
        var errorCount: Int = 0
        var lastRefreshTime: Date?
        var appStartTime: Date = Date()
        var lastSpaceChangeTime: Date?
    }

    enum LogLevel: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
        case fatal = "FATAL"
    }

    private init() {
        // Setup date formatter
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        // Create log file in Application Support directory
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let logDir = appSupport.appendingPathComponent("YabaiIndicator/Logs", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

        // Use date-based log file name
        let logDateFormatter = DateFormatter()
        logDateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = logDateFormatter.string(from: Date())
        logFileURL = logDir.appendingPathComponent("yabai-indicator-\(dateString).log")

        // Open or create log file
        setupFileHandle()

        // Setup crash handlers
        setupCrashHandlers()

        // Log startup
        info("========================================")
        info("YabaiIndicator Started")
        info(
            "Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")"
        )
        info("Build: \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown")")
        info("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        info("Process ID: \(ProcessInfo.processInfo.processIdentifier)")
        info("Log file: \(logFileURL.path)")
        info("========================================")
    }

    private func setupFileHandle() {
        // Check if file exists and rotate if too large
        if FileManager.default.fileExists(atPath: logFileURL.path) {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
                let size = attrs[.size] as? Int,
                size > maxLogSize
            {
                rotateLogFile()
            }
        } else {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }

        fileHandle = try? FileHandle(forWritingTo: logFileURL)
        fileHandle?.seekToEndOfFile()
    }

    private func rotateLogFile() {
        // Rename current log to .old
        let oldURL = logFileURL.deletingPathExtension().appendingPathExtension("old.log")
        try? FileManager.default.removeItem(at: oldURL)
        try? FileManager.default.moveItem(at: logFileURL, to: oldURL)

        // Create new file
        FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
    }

    private func setupCrashHandlers() {
        // Register for uncaught exception handler
        NSSetUncaughtExceptionHandler { exception in
            Logger.shared.fatal("Uncaught Exception: \(exception.name.rawValue)")
            Logger.shared.fatal("Reason: \(exception.reason ?? "unknown")")
            Logger.shared.fatal(
                "Call Stack:\n\(exception.callStackSymbols.joined(separator: "\n"))")
            Logger.shared.logStats()
            Logger.shared.flush()
        }

        // Setup signal handlers for common crash signals
        setupSignalHandler(signal: SIGABRT)
        setupSignalHandler(signal: SIGSEGV)
        setupSignalHandler(signal: SIGBUS)
        setupSignalHandler(signal: SIGILL)
        setupSignalHandler(signal: SIGFPE)
    }

    private func setupSignalHandler(signal signalNum: Int32) {
        let handler: @convention(c) (Int32) -> Void = { sig in
            let signalName: String
            switch sig {
            case SIGABRT: signalName = "SIGABRT (Abort)"
            case SIGSEGV: signalName = "SIGSEGV (Segmentation Fault)"
            case SIGBUS: signalName = "SIGBUS (Bus Error)"
            case SIGILL: signalName = "SIGILL (Illegal Instruction)"
            case SIGFPE: signalName = "SIGFPE (Floating Point Exception)"
            default: signalName = "Signal \(sig)"
            }

            // Write directly to file since we might be in a bad state
            let message = """

                ========================================
                FATAL CRASH: \(signalName)
                Time: \(Date())
                ========================================

                """
            if let data = message.data(using: .utf8) {
                Logger.shared.fileHandle?.write(data)
                Logger.shared.fileHandle?.synchronizeFile()
            }

            // Re-raise signal to get default behavior
            Darwin.signal(sig, SIG_DFL)
            Darwin.raise(sig)
        }

        Darwin.signal(signalNum, handler)
    }

    // MARK: - Logging Methods

    func log(
        _ level: LogLevel, _ message: String, file: String = #file, function: String = #function,
        line: Int = #line
    ) {
        let timestamp = dateFormatter.string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        let threadInfo =
            Thread.isMainThread ? "Main" : "BG-\(Thread.current.description.hashValue % 1000)"

        let logMessage =
            "[\(timestamp)] [\(level.rawValue)] [\(threadInfo)] [\(fileName):\(line)] \(function) - \(message)\n"

        logQueue.async { [weak self] in
            guard let self = self else { return }

            if let data = logMessage.data(using: .utf8) {
                self.fileHandle?.write(data)
            }

            // Periodic flush
            let now = Date()
            if now.timeIntervalSince(self.lastFlushTime) > self.flushInterval {
                self.fileHandle?.synchronizeFile()
                self.lastFlushTime = now
            }
        }

        // Also log to console in debug builds
        #if DEBUG
            print(logMessage, terminator: "")
        #endif

        // Track error count
        if level == .error || level == .fatal {
            logQueue.async { [weak self] in
                self?.stats.errorCount += 1
            }
        }
    }

    func debug(
        _ message: String, file: String = #file, function: String = #function, line: Int = #line
    ) {
        log(.debug, message, file: file, function: function, line: line)
    }

    func info(
        _ message: String, file: String = #file, function: String = #function, line: Int = #line
    ) {
        log(.info, message, file: file, function: function, line: line)
    }

    func warning(
        _ message: String, file: String = #file, function: String = #function, line: Int = #line
    ) {
        log(.warning, message, file: file, function: function, line: line)
    }

    func error(
        _ message: String, file: String = #file, function: String = #function, line: Int = #line
    ) {
        log(.error, message, file: file, function: function, line: line)
    }

    func fatal(
        _ message: String, file: String = #file, function: String = #function, line: Int = #line
    ) {
        log(.fatal, message, file: file, function: function, line: line)
    }

    // MARK: - Event Tracking

    func trackRefresh() {
        logQueue.async { [weak self] in
            self?.stats.refreshCount += 1
            self?.stats.lastRefreshTime = Date()
        }
    }

    func trackSpaceChange() {
        logQueue.async { [weak self] in
            self?.stats.spaceChangeCount += 1
            self?.stats.lastSpaceChangeTime = Date()
        }
    }

    func trackDisplayChange() {
        logQueue.async { [weak self] in
            self?.stats.displayChangeCount += 1
        }
    }

    func trackSocketMessage() {
        logQueue.async { [weak self] in
            self?.stats.socketMessageCount += 1
        }
    }

    // MARK: - Stats and Diagnostics

    func logStats() {
        logQueue.async { [weak self] in
            guard let self = self else { return }

            let uptime = Date().timeIntervalSince(self.stats.appStartTime)
            let uptimeFormatted = String(format: "%.2f hours", uptime / 3600)

            let statsMessage = """

                ========== Runtime Statistics ==========
                Uptime: \(uptimeFormatted)
                Total Refreshes: \(self.stats.refreshCount)
                Space Changes: \(self.stats.spaceChangeCount)
                Display Changes: \(self.stats.displayChangeCount)
                Socket Messages: \(self.stats.socketMessageCount)
                Errors: \(self.stats.errorCount)
                Last Refresh: \(self.stats.lastRefreshTime?.description ?? "never")
                Last Space Change: \(self.stats.lastSpaceChangeTime?.description ?? "never")
                Memory Usage: \(self.getMemoryUsage())
                =========================================

                """

            if let data = statsMessage.data(using: .utf8) {
                self.fileHandle?.write(data)
            }
        }
    }

    func logMemoryWarning() {
        warning("Memory warning received - Memory: \(getMemoryUsage())")
        logStats()
    }

    private func getMemoryUsage() -> String {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            let usedMB = Double(info.resident_size) / 1024.0 / 1024.0
            return String(format: "%.2f MB", usedMB)
        }
        return "unknown"
    }

    func flush() {
        logQueue.sync {
            fileHandle?.synchronizeFile()
        }
    }

    deinit {
        info("YabaiIndicator Shutting Down")
        logStats()
        flush()
        try? fileHandle?.close()
    }
}

// MARK: - Convenience Global Functions

func logDebug(
    _ message: String, file: String = #file, function: String = #function, line: Int = #line
) {
    Logger.shared.debug(message, file: file, function: function, line: line)
}

func logInfo(
    _ message: String, file: String = #file, function: String = #function, line: Int = #line
) {
    Logger.shared.info(message, file: file, function: function, line: line)
}

func logWarning(
    _ message: String, file: String = #file, function: String = #function, line: Int = #line
) {
    Logger.shared.warning(message, file: file, function: function, line: line)
}

func logError(
    _ message: String, file: String = #file, function: String = #function, line: Int = #line
) {
    Logger.shared.error(message, file: file, function: function, line: line)
}

func logFatal(
    _ message: String, file: String = #file, function: String = #function, line: Int = #line
) {
    Logger.shared.fatal(message, file: file, function: function, line: line)
}
