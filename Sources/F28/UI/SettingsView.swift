import AppKit
import F28Core
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    let engine: () -> String

    var body: some View {
        TabView {
            FocusTab(prefs: prefs)
                .tabItem { Label("Focus", systemImage: "camera.aperture") }
            BehaviorTab(prefs: prefs)
                .tabItem { Label("Behavior", systemImage: "rectangle.3.group") }
            GesturesTab(prefs: prefs)
                .tabItem { Label("Gestures", systemImage: "cursorarrow.motionlines") }
            AppsTab(prefs: prefs)
                .tabItem { Label("Apps", systemImage: "square.grid.2x2") }
            ShortcutsTab()
                .tabItem { Label("Shortcuts", systemImage: "command") }
            AboutTab(engine: engine)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 600)
    }
}

// MARK: - Building blocks

private struct PercentSlider: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var format: (Double) -> String = { "\(Int(($0 * 100).rounded()))%" }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(value: $value, in: range)
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }
}

private struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Focus

private struct FocusTab: View {
    @ObservedObject var prefs: Preferences

    private var tintColor: Binding<Color> {
        Binding(get: { Color(nsColor: prefs.customTint) },
                set: { prefs.customTint = NSColor($0) })
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $prefs.enabled) {
                    Text("Focus").font(.headline)
                    Text("Blur everything except the window you're working in.")
                }
            }
            Section("Look") {
                Picker("Mode", selection: $prefs.mode) {
                    ForEach(FocusMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Caption(prefs.mode.blurb)
                PercentSlider(title: "Blur", value: $prefs.blur)
                Picker("Tint", selection: $prefs.tint) {
                    ForEach(TintStyle.allCases) { Text($0.title).tag($0) }
                }
                if prefs.tint == .custom {
                    ColorPicker("Tint color", selection: tintColor, supportsOpacity: false)
                }
                PercentSlider(title: "Window dimming", value: $prefs.dim)
                PercentSlider(title: "Grain", value: $prefs.grain)
                Toggle("Monochrome", isOn: $prefs.monochrome)
            }
            Section("Transition") {
                Picker("Reveal effect", selection: $prefs.revealEffect) {
                    ForEach(RevealEffect.allCases) { Text($0.title).tag($0) }
                }
                PercentSlider(title: "Duration", value: $prefs.transitionDuration, range: 0.1...1.0,
                              format: { String(format: "%.2fs", $0) })
                    .disabled(prefs.revealEffect == .none)
                Caption("Fade lets the window you leave melt into the blur. Focus Pull also racks the background in and out of focus, like a lens.")
            }
            Section {
                Button("Restore Default Look") { prefs.resetLook() }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Behavior

private struct BehaviorTab: View {
    @ObservedObject var prefs: Preferences
    @StateObject private var login = LoginItem()

    var body: some View {
        Form {
            Section("Focus") {
                Toggle(isOn: $prefs.appWide) {
                    Text("App-wide focus")
                    Text("Show all windows of the same app.")
                }
                Picker("Multi-screen", selection: $prefs.multiScreen) {
                    ForEach(MultiScreenMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Caption(prefs.multiScreen.blurb)
                Toggle(isOn: $prefs.blurStageManager) {
                    Text("Blur Stage Manager")
                    Text("Cover thumbnails with the overlay.")
                }
            }
            Section("Desktop") {
                Toggle(isOn: $prefs.autoHideBars) {
                    Text("Auto-hide menu bar & Dock")
                    Text("While focus is on. Your own settings come back when it's off. macOS asks once to let f/2.8 control System Events.")
                }
                Toggle(isOn: $prefs.showControls) {
                    Text("Show floating controls")
                    Text("A small dot you can click to toggle focus. Drag it anywhere; right-click for options.")
                }
            }
            Section("Startup") {
                Toggle(isOn: $prefs.showInDock) {
                    Text("Show in Dock")
                    Text("Click the Dock icon to open these settings. Turn off to live in the menu bar only — on a crowded menu bar, macOS may hide the icon behind the notch.")
                }
                Toggle("Launch at login", isOn: Binding(get: { login.enabled }, set: { login.set($0) }))
                if let error = login.error {
                    Caption(error)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Launch-at-login state, backed by `SMAppService`.
@MainActor
private final class LoginItem: ObservableObject {
    @Published private(set) var enabled = SMAppService.mainApp.status == .enabled
    @Published private(set) var error: String?

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch {
            self.error = "Couldn't change the login item: \(error.localizedDescription). Move f/2.8 to Applications and try again."
        }
        enabled = SMAppService.mainApp.status == .enabled
    }
}

// MARK: - Gestures

private struct GesturesTab: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Form {
            Section("Shake") {
                Toggle(isOn: $prefs.shakeToToggle) {
                    Text("Shake to toggle")
                    Text("Shake the cursor left and right to turn focus on or off.")
                }
                Toggle(isOn: $prefs.shakeToPeek) {
                    Text("Hold ⇧ + shake to peek")
                    Text("Reveals everything for as long as you keep Shift held.")
                }
                LabeledContent("Sensitivity") {
                    HStack(spacing: 8) {
                        Text("Low").foregroundStyle(.secondary)
                        Slider(value: $prefs.shakeSensitivity, in: 0...1)
                        Text("High").foregroundStyle(.secondary)
                    }
                }
                .disabled(!prefs.shakeToToggle && !prefs.shakeToPeek)
            }
            Section {
                Caption("Shakes are read from cursor movement only — no Accessibility or Input Monitoring permission is needed. Dragging a window never counts as a shake.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Apps

private struct AppIdentity: Identifiable, Hashable {
    let bundleID: String
    var id: String { bundleID }

    var url: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }
    var name: String {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let name = app.localizedName { return name }
        if let url { return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "") }
        return bundleID
    }
    var icon: NSImage {
        if let url { return NSWorkspace.shared.icon(forFile: url.path) }
        return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
    }

    static func running() -> [AppIdentity] {
        let ids = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0 != .current }
            .compactMap(\.bundleIdentifier)
        return Array(Set(ids)).map(AppIdentity.init).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

private struct AppLabel: View {
    let app: AppIdentity
    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: app.icon).resizable().frame(width: 20, height: 20)
            Text(app.name)
        }
    }
}

private struct AppsTab: View {
    @ObservedObject var prefs: Preferences
    @StateObject private var model = AppsModel()

    var body: some View {
        Form {
            Section {
                if prefs.ignoredApps.isEmpty {
                    Caption("No ignored apps. Press ⌃⌥⌘E to ignore whichever app is in front.")
                }
                ForEach(prefs.ignoredApps, id: \.self) { bundle in
                    HStack {
                        AppLabel(app: AppIdentity(bundleID: bundle))
                        Spacer()
                        Text("Ignored").foregroundStyle(.secondary)
                        Button { prefs.toggleIgnored(bundle) } label: { Image(systemName: "minus.circle.fill") }
                            .buttonStyle(.borderless)
                            .help("Stop ignoring")
                    }
                }
                HStack {
                    Menu("Add Running App") {
                        ForEach(model.running.filter { !prefs.isIgnored($0.bundleID) }) { app in
                            Button(app.name) { prefs.toggleIgnored(app.bundleID) }
                        }
                    }
                    .fixedSize()
                    Button("Choose…", action: chooseIgnoredApp)
                }
            } header: {
                Text("Ignored Apps")
            } footer: {
                Caption("f/2.8 steps aside while an ignored app is in front.")
            }

            Section {
                if prefs.appGroups.isEmpty {
                    Caption("No groups yet.")
                }
                ForEach(Array(prefs.appGroups.enumerated()), id: \.offset) { index, group in
                    HStack {
                        ForEach(group, id: \.self) { bundle in
                            Image(nsImage: AppIdentity(bundleID: bundle).icon).resizable().frame(width: 20, height: 20)
                        }
                        Text(group.map { AppIdentity(bundleID: $0).name }.joined(separator: " & "))
                        Spacer()
                        Button { prefs.appGroups.remove(at: index) } label: { Image(systemName: "minus.circle.fill") }
                            .buttonStyle(.borderless)
                            .help("Remove group")
                    }
                }
                HStack {
                    Picker("", selection: $model.groupA) {
                        Text("Choose app").tag("")
                        ForEach(model.running) { Text($0.name).tag($0.bundleID) }
                    }
                    .labelsHidden()
                    Text("&")
                    Picker("", selection: $model.groupB) {
                        Text("Choose app").tag("")
                        ForEach(model.running) { Text($0.name).tag($0.bundleID) }
                    }
                    .labelsHidden()
                    Button("Pair") {
                        prefs.addGroup(model.groupA, model.groupB)
                        model.groupA = ""
                        model.groupB = ""
                    }
                    .disabled(model.groupA.isEmpty || model.groupB.isEmpty || model.groupA == model.groupB)
                }
            } header: {
                Text("App Groups")
            } footer: {
                Caption("Pair apps that stay focused together — say, your editor and its docs. Windows of both stay sharp while they're on top.")
            }
        }
        .formStyle(.grouped)
        .onAppear { model.running = AppIdentity.running() }
    }

    private func chooseIgnoredApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = "Ignore"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let bundle = Bundle(url: url)?.bundleIdentifier, !prefs.isIgnored(bundle) {
                prefs.toggleIgnored(bundle)
            }
        }
    }
}

@MainActor
private final class AppsModel: ObservableObject {
    @Published var running = AppIdentity.running()
    @Published var groupA = ""
    @Published var groupB = ""
}

// MARK: - Shortcuts

private struct ShortcutsTab: View {
    private let rows: [(String, String)] = [
        ("Toggle f/2.8", Shortcuts.toggle.display),
        ("Switch Mode", Shortcuts.switchMode.display),
        ("Ignore App", Shortcuts.ignoreApp.display),
        ("Toggle Controls", Shortcuts.toggleControls.display),
    ]

    var body: some View {
        Form {
            Section {
                ForEach(rows, id: \.0) { row in
                    LabeledContent(row.0) {
                        Text(row.1)
                            .font(.system(.body, design: .rounded).weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
                    }
                }
            } footer: {
                Caption("Shortcuts work in every app. If one is already taken by another app, it's listed in Console as “could not register”.")
            }
            Section("Gestures") {
                LabeledContent("Toggle", value: "Shake")
                LabeledContent("Peek", value: "Hold ⇧ + Shake")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

private struct AboutTab: View {
    let engine: () -> String

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 128, height: 128)
            Text("f/2.8").font(.system(size: 34, weight: .bold, design: .rounded))
            Text("Shallow depth of field for your desktop.")
                .font(.title3).foregroundStyle(.secondary)
            Text(version).foregroundStyle(.secondary)
            Divider().frame(width: 260).padding(.vertical, 6)
            VStack(spacing: 6) {
                Text("No analytics. No network. Nothing leaves this Mac.")
                Text("No Accessibility or Screen Recording permission needed.")
                Text("Blur engine: \(engine())").foregroundStyle(.tertiary)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Window

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let prefs: Preferences
    private let engine: () -> String
    private var window: NSWindow?

    init(prefs: Preferences, engine: @escaping () -> String) {
        self.prefs = prefs
        self.engine = engine
    }

    func show() {
        let window = self.window ?? makeWindow()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView(prefs: prefs, engine: engine))
        let window = NSWindow(contentViewController: hosting)
        window.title = "f/2.8"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("f28.settings")
        self.window = window
        return window
    }

    func windowWillClose(_ notification: Notification) {
        // Hand focus back to whatever was in front before Settings opened.
        DispatchQueue.main.async { NSApp.hide(nil) }
    }
}
