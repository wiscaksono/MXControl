import Foundation
import os

/// Global logger for MXControl.
public let logger = Logger(subsystem: "com.mxcontrol.app", category: "general")

// MARK: - Debug File Logger

#if DEBUG
/// Write debug log directly to file, bypassing macOS privacy filtering.
private let debugLogFile: FileHandle? = {
    let path = "/tmp/mxcontrol_debug.log"
    FileManager.default.createFile(atPath: path, contents: nil)
    return FileHandle(forWritingAtPath: path)
}()

nonisolated(unsafe) private let debugDateFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

nonisolated(unsafe) private let debugLogQueue = DispatchQueue(label: "com.mxcontrol.debuglog")

public func debugLog(_ message: String) {
    let ts = debugDateFormatter.string(from: Date())
    let line = "[\(ts)] \(message)\n"
    debugLogQueue.async {
        debugLogFile?.seekToEndOfFile()
        debugLogFile?.write(line.data(using: .utf8) ?? Data())
    }
}
#else
@inline(__always) public func debugLog(_ message: @autoclosure () -> String) {}
#endif
