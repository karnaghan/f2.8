import AppKit

/// The app's own menu bar, shown while f/2.8 has a Dock icon and is the active app.
@MainActor
enum MainMenu {
    static func make(commands: AppCommands) -> NSMenu {
        let target = MenuTarget.shared
        target.commands = commands
        let main = NSMenu()

        let app = NSMenu(title: "f/2.8")
        app.addItem(withTitle: "About f/2.8", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        let settings = app.addItem(withTitle: "Settings…", action: #selector(MenuTarget.showSettings), keyEquivalent: ",")
        settings.target = target
        app.addItem(.separator())
        app.addItem(withTitle: "Hide f/2.8", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = app.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit f/2.8", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu(app))

        let hyper: NSEvent.ModifierFlags = [.control, .option, .command]
        let focus = NSMenu(title: "Focus")
        for (title, action, key) in [
            ("Toggle Focus", #selector(MenuTarget.toggleFocus), "f"),
            ("Switch Mode", #selector(MenuTarget.switchMode), "m"),
            ("Show Controls", #selector(MenuTarget.toggleControls), "c"),
        ] {
            let item = focus.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = hyper
            item.target = target
        }
        main.addItem(submenu(focus))

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        main.addItem(submenu(window))
        NSApp.windowsMenu = window
        return main
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}

@MainActor
private final class MenuTarget: NSObject {
    static let shared = MenuTarget()
    weak var commands: AppCommands?

    @objc func showSettings() { commands?.showSettings() }
    @objc func toggleFocus() { commands?.toggleFocus() }
    @objc func switchMode() { commands?.switchMode() }
    @objc func toggleControls() { commands?.toggleControls() }
}
