import Foundation

nonisolated struct AppleScriptError: Error, Equatable, Sendable {
    let code: Int
    let message: String

    /// -1743: the user hasn't allowed (or has denied) Automation for the target app.
    var isNotAuthorized: Bool { code == -1743 }
    /// -600 / -609: the target app isn't running or quit mid-call.
    var isAppNotRunning: Bool { code == -600 || code == -609 }
}

/// Runs AppleScript off the main thread on one serial queue.
///
/// `NSAppleScript` is not thread-safe, so every script is compiled and executed on the same
/// queue and the parsed (Sendable) result is handed back on the main actor. A slow or
/// unresponsive target app therefore never blocks the Touch Bar UI.
nonisolated enum AppleScriptRunner {
    private static let queue = DispatchQueue(label: "com.dynamictouchbar.applescript", qos: .userInitiated)
    nonisolated(unsafe) private static var compiled: [String: NSAppleScript] = [:]

    static func run<T: Sendable>(
        _ source: String,
        parse: @escaping @Sendable (NSAppleEventDescriptor) -> T?,
        completion: @escaping @MainActor @Sendable (Result<T?, AppleScriptError>) -> Void
    ) {
        queue.async {
            let result = execute(source, parse: parse)
            Task { @MainActor in completion(result) }
        }
    }

    /// Fire-and-forget convenience for commands.
    static func run(_ source: String, completion: (@MainActor @Sendable (AppleScriptError?) -> Void)? = nil) {
        run(source, parse: { _ in true }) { result in
            if case .failure(let error) = result { completion?(error) } else { completion?(nil) }
        }
    }

    private static func execute<T>(_ source: String, parse: (NSAppleEventDescriptor) -> T?) -> Result<T?, AppleScriptError> {
        let script: NSAppleScript
        if let cached = compiled[source] {
            script = cached
        } else {
            guard let created = NSAppleScript(source: source) else {
                return .failure(AppleScriptError(code: -1, message: "Could not create script"))
            }
            var compileError: NSDictionary?
            created.compileAndReturnError(&compileError)
            if let compileError {
                return .failure(error(from: compileError))
            }
            compiled[source] = created
            script = created
        }
        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            return .failure(error(from: errorInfo))
        }
        return .success(parse(descriptor))
    }

    private static func error(from info: NSDictionary) -> AppleScriptError {
        let code = (info[NSAppleScript.errorNumber] as? Int) ?? -1
        let message = (info[NSAppleScript.errorMessage] as? String) ?? "AppleScript error \(code)"
        return AppleScriptError(code: code, message: message)
    }

    /// Escapes a Swift string for embedding in AppleScript source.
    static func quoted(_ string: String) -> String {
        "\"" + string.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

nonisolated extension NSAppleEventDescriptor {
    /// Items of an AppleScript list (1-based in the Apple Event world).
    var listItems: [NSAppleEventDescriptor] {
        guard numberOfItems > 0 else { return [] }
        return (1...numberOfItems).compactMap { atIndex($0) }
    }
}
