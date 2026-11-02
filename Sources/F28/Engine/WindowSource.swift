import AppKit
import F28Core

/// Reads the on-screen window list. Needs no permissions: window numbers, owners, layers and
/// bounds are public; only window titles would require Screen Recording access.
@MainActor
final class WindowSource {
    /// System processes whose layer-0 windows must never become a focus target.
    static let systemOwners: Set<String> = [
        "Window Server", "Dock", "WindowManager", "Control Center", "Notification Center",
        "SystemUIServer", "Spotlight", "screencaptureui", "TextInputMenuAgent",
    ]

    private var bundleCache: [pid_t: String] = [:]

    func snapshot() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        var windows: [WindowInfo] = []
        windows.reserveCapacity(list.count)
        for entry in list {
            guard let number = entry[kCGWindowNumber as String] as? NSNumber,
                  let pid = entry[kCGWindowOwnerPID as String] as? NSNumber,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }
            windows.append(WindowInfo(
                id: number.uint32Value,
                pid: pid.int32Value,
                bundleID: bundleID(for: pid.int32Value),
                ownerName: entry[kCGWindowOwnerName as String] as? String,
                layer: (entry[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
                bounds: bounds,
                alpha: (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            ))
        }
        return windows
    }

    func forget(pid: pid_t) { bundleCache[pid] = nil }

    private func bundleID(for pid: pid_t) -> String? {
        if let cached = bundleCache[pid] { return cached.isEmpty ? nil : cached }
        let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        bundleCache[pid] = bundle ?? ""
        return bundle
    }
}
