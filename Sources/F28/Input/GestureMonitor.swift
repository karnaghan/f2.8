import AppKit
import F28Core

/// Watches the cursor for shakes. Global mouse-move monitoring needs no special permission.
@MainActor
final class GestureMonitor {
    /// Called with the modifier keys held when the shake was recognised.
    var onShake: ((NSEvent.ModifierFlags) -> Void)?

    private var detector = ShakeDetector()
    private var globalMonitor: Any?
    private var localMonitor: Any?

    var sensitivity: Double {
        get { detector.sensitivity }
        set { detector.sensitivity = newValue }
    }

    func start() {
        guard globalMonitor == nil else { return }
        // Only plain moves: dragging a window back and forth must not count as a shake.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            MainActor.assumeIsolated { self?.sample(event.timestamp) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            MainActor.assumeIsolated { self?.sample(event.timestamp) }
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func sample(_ timestamp: TimeInterval) {
        if detector.feed(NSEvent.mouseLocation, at: timestamp) {
            onShake?(NSEvent.modifierFlags)
        }
    }
}
