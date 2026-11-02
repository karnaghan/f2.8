import AppKit

/// Everything the menus and shortcuts can ask the app to do.
@MainActor
protocol AppCommands: AnyObject {
    func toggleFocus()
    func switchMode()
    func setMode(_ mode: FocusMode)
    func ignoreFrontmostApp()
    func toggleControls()
    func showSettings()
}

/// The aperture in the menu bar.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let prefs: Preferences
    private weak var commands: AppCommands?
    private let menu = NSMenu()

    init(prefs: Preferences, commands: AppCommands) {
        self.prefs = prefs
        self.commands = commands
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        item.button?.setAccessibilityTitle("f/2.8")
        refreshIcon()
    }

    func refreshIcon() {
        guard let button = item.button else { return }
        let name = prefs.enabled ? "camera.aperture" : "circle.dashed"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "f/2.8")?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .medium))
        image?.isTemplate = true
        button.image = image
        button.appearsDisabled = !prefs.enabled
        button.toolTip = prefs.enabled ? "f/2.8 — focus is on" : "f/2.8 — focus is off"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        Self.populate(menu, prefs: prefs, target: self, includeSlider: true)
    }

    /// Shared by the menu bar item and the floating dot's context menu.
    static func populate(_ menu: NSMenu, prefs: Preferences, target: StatusMenuController, includeSlider: Bool) {
        let hyper: NSEvent.ModifierFlags = [.control, .option, .command]

        let header = NSMenuItem(title: "f/2.8", action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.attributedTitle = NSAttributedString(string: "f/2.8", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .bold),
        ])
        menu.addItem(header)

        let toggle = NSMenuItem(title: "Focus", action: #selector(toggleFocus), keyEquivalent: "f")
        toggle.keyEquivalentModifierMask = hyper
        toggle.state = prefs.enabled ? .on : .off
        toggle.target = target
        menu.addItem(toggle)
        menu.addItem(.separator())

        for mode in FocusMode.allCases {
            let entry = NSMenuItem(title: mode.title, action: #selector(chooseMode(_:)), keyEquivalent: "")
            entry.representedObject = mode.rawValue
            entry.state = prefs.mode == mode ? .on : .off
            entry.target = target
            entry.toolTip = mode.blurb
            menu.addItem(entry)
        }
        let switcher = NSMenuItem(title: "Switch Mode", action: #selector(switchMode), keyEquivalent: "m")
        switcher.keyEquivalentModifierMask = hyper
        switcher.target = target
        menu.addItem(switcher)

        if includeSlider {
            let slider = NSMenuItem()
            slider.view = MenuSliderView(title: "Blur", value: prefs.blur) { [weak prefs] value in
                prefs?.blur = value
            }
            menu.addItem(slider)
        }
        menu.addItem(.separator())

        let front = NSWorkspace.shared.frontmostApplication
        if let front, front != .current, let bundle = front.bundleIdentifier {
            let name = front.localizedName ?? bundle
            let ignore = NSMenuItem(title: "Ignore \(name)", action: #selector(ignoreFrontmost), keyEquivalent: "e")
            ignore.keyEquivalentModifierMask = hyper
            ignore.state = prefs.isIgnored(bundle) ? .on : .off
            ignore.target = target
            menu.addItem(ignore)
        }
        let controls = NSMenuItem(title: "Show Controls", action: #selector(toggleControls), keyEquivalent: "c")
        controls.keyEquivalentModifierMask = hyper
        controls.state = prefs.showControls ? .on : .off
        controls.target = target
        menu.addItem(controls)
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = target
        menu.addItem(settings)
        let quit = NSMenuItem(title: "Quit f/2.8", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    func contextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        Self.populate(menu, prefs: prefs, target: self, includeSlider: false)
        return menu
    }

    @objc private func toggleFocus() { commands?.toggleFocus() }
    @objc private func switchMode() { commands?.switchMode() }
    @objc private func ignoreFrontmost() { commands?.ignoreFrontmostApp() }
    @objc private func toggleControls() { commands?.toggleControls() }
    @objc private func showSettings() { commands?.showSettings() }
    @objc private func chooseMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = FocusMode(rawValue: raw) else { return }
        commands?.setMode(mode)
    }
}

/// "Blur  ───●──" inside the menu.
private final class MenuSliderView: NSView {
    private let slider: NSSlider
    private let onChange: (Double) -> Void

    init(title: String, value: Double, onChange: @escaping (Double) -> Void) {
        self.onChange = onChange
        slider = NSSlider(value: value, minValue: 0, maxValue: 1, target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 30))
        slider.target = self
        slider.action = #selector(changed)
        slider.isContinuous = true
        slider.controlSize = .small

        let label = NSTextField(labelWithString: title)
        label.font = .menuFont(ofSize: 0)
        label.textColor = .secondaryLabelColor
        for view in [label, slider] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            slider.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 10),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            slider.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func changed() { onChange(slider.doubleValue) }
}
