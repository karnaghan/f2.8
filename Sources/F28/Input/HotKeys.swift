import Carbon.HIToolbox
import Foundation

/// System-wide keyboard shortcuts via Carbon's `RegisterEventHotKey`, which needs no
/// Accessibility permission.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    struct Shortcut {
        let keyCode: UInt32
        let modifiers: UInt32
        let display: String
    }

    /// ⌃⌥⌘ + key.
    static func hyper(_ keyCode: Int, _ letter: String) -> Shortcut {
        Shortcut(keyCode: UInt32(keyCode), modifiers: UInt32(controlKey | optionKey | cmdKey), display: "⌃⌥⌘\(letter)")
    }

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var installed = false
    private var nextID: UInt32 = 1
    private(set) var failures: [String] = []

    func register(_ shortcut: Shortcut, handler: @escaping () -> Void) {
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4632_3820), id: id) // 'F28 '
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            refs.append(ref)
            handlers[id] = handler
        } else {
            failures.append(shortcut.display)
            NSLog("f/2.8: could not register \(shortcut.display) (status \(status)); another app may own it")
        }
    }

    fileprivate func fire(_ id: UInt32) { handlers[id]?() }

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            let id = hotKeyID.id
            DispatchQueue.main.async { MainActor.assumeIsolated { HotKeyCenter.shared.fire(id) } }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

enum Shortcuts {
    @MainActor static let toggle = HotKeyCenter.hyper(kVK_ANSI_F, "F")
    @MainActor static let switchMode = HotKeyCenter.hyper(kVK_ANSI_M, "M")
    @MainActor static let ignoreApp = HotKeyCenter.hyper(kVK_ANSI_E, "E")
    @MainActor static let toggleControls = HotKeyCenter.hyper(kVK_ANSI_C, "C")
}
