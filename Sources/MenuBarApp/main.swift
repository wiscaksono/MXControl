import AppCore
import AppKit

// No `@main`: top-level code lets the headless path exit before AppKit starts.
if CommandLine.arguments.contains("--self-check") {
    SelfCheck.run()
    exit(EXIT_SUCCESS)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
