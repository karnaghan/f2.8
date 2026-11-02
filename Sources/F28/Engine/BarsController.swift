import Foundation

/// Auto-hides the Dock and menu bar while focus is on, restoring the user's own settings after.
///
/// Uses System Events' `dock preferences`, the supported scripting interface for both
/// switches. macOS asks once for permission to control System Events.
final class BarsController: @unchecked Sendable {
    private let queue = DispatchQueue(label: "f28.bars")
    private var saved: (dock: Bool, menuBar: Bool)? // touched on `queue` only
    private var hidden = false // touched on the main thread only

    func setHidden(_ hide: Bool) {
        guard hide != hidden else { return }
        hidden = hide
        queue.async { hide ? self.engage() : self.restore() }
    }

    /// Restore synchronously (on quit).
    func restoreNow() {
        guard hidden else { return }
        hidden = false
        queue.sync { restore() }
    }

    private func engage() {
        if saved == nil { saved = read() ?? (false, false) }
        run("""
        tell application "System Events" to tell dock preferences
            set autohide to true
            set autohide menu bar to true
        end tell
        """)
    }

    private func restore() {
        guard let saved else { return }
        self.saved = nil
        run("""
        tell application "System Events" to tell dock preferences
            set autohide to \(saved.dock)
            set autohide menu bar to \(saved.menuBar)
        end tell
        """)
    }

    private func read() -> (dock: Bool, menuBar: Bool)? {
        let result = run("""
        tell application "System Events" to tell dock preferences
            return {autohide, autohide menu bar}
        end tell
        """)
        guard let result, result.numberOfItems == 2,
              let dock = result.atIndex(1)?.booleanValue,
              let menuBar = result.atIndex(2)?.booleanValue else { return nil }
        return (dock, menuBar)
    }

    @discardableResult
    private func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { NSLog("f/2.8: System Events script failed: \(error)") }
        return result
    }
}
