import CoreGraphics

/// Decides, for every display, which window the blur overlay should sit directly beneath.
///
/// The overlay is a normal-level window, so anything ordered above it stays sharp and
/// everything below it is blurred. Resolution therefore reduces to picking a z-order slot.
public enum FocusResolver {

    /// The display a window belongs to: the one containing its centre, else the one it overlaps most.
    public static func screenID(for rect: CGRect, in screens: [ScreenInfo]) -> UInt32? {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        if let hit = screens.first(where: { $0.frame.contains(centre) }) {
            return hit.id
        }
        var best: (id: UInt32, area: CGFloat)?
        for screen in screens {
            let overlap = screen.frame.intersection(rect)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > (best?.area ?? 0) { best = (screen.id, area) }
        }
        return best?.id
    }

    /// Bundle IDs that share focus with `bundleID` through an app group (excluding itself).
    public static func partners(of bundleID: String?, groups: [[String]]) -> Set<String> {
        guard let bundleID else { return [] }
        var result = Set<String>()
        for group in groups where group.contains(bundleID) {
            result.formUnion(group)
        }
        result.remove(bundleID)
        return result
    }

    /// - Parameters:
    ///   - windows: on-screen windows, front-to-back, with f/2.8's own overlays already removed.
    ///   - frontPID / frontBundleID: the frontmost application.
    public static func resolve(windows: [WindowInfo], frontPID: Int32?, frontBundleID: String?,
                               screens: [ScreenInfo], options: FocusOptions) -> FocusState {
        var state = FocusState()
        for screen in screens { state.screens[screen.id] = .hidden }

        guard let frontPID else { return state }
        if let bundle = frontBundleID, options.ignoredBundleIDs.contains(bundle) { return state }

        let minSide = options.minimumWindowSide
        let normal = windows.filter {
            $0.layer == 0 && $0.alpha > 0 && $0.bounds.width >= minSide && $0.bounds.height >= minSide
        }
        guard let focusIndex = normal.firstIndex(where: { $0.pid == frontPID }) else { return state }

        // Grow a contiguous run below the focused window: more windows of the same app
        // (when app-wide focus is on) and windows of apps paired with it in a group.
        let partnerIDs = partners(of: frontBundleID, groups: options.appGroups)
        var last = focusIndex
        while last + 1 < normal.count {
            let next = normal[last + 1]
            let sameApp = next.pid == frontPID
            let partner = next.bundleID.map { partnerIDs.contains($0) } ?? false
            guard (sameApp && options.appWide) || partner else { break }
            last += 1
        }

        let focused = normal[focusIndex]
        let activeScreen = screenID(for: focused.bounds, in: screens)
        state.focusedWindowID = focused.id
        state.activeScreenID = activeScreen
        state.focusIsOnTop = focusIndex == 0

        let focusTarget = ScreenTarget(targetID: normal[last].id, sharpIDs: normal[...last].map(\.id))

        switch options.multiScreen {
        case .global:
            for screen in screens { state.screens[screen.id] = .focus(focusTarget) }

        case .perScreen:
            for screen in screens {
                if screen.id == activeScreen {
                    state.screens[screen.id] = .focus(focusTarget)
                    continue
                }
                // Other displays keep the window you used last there: the topmost one on that display.
                guard let top = normal.firstIndex(where: { screenID(for: $0.bounds, in: screens) == screen.id }) else {
                    continue
                }
                let window = normal[top]
                if let bundle = window.bundleID, options.ignoredBundleIDs.contains(bundle) { continue }
                var end = top
                if options.appWide {
                    while end + 1 < normal.count, normal[end + 1].pid == window.pid { end += 1 }
                }
                state.screens[screen.id] = .focus(ScreenTarget(targetID: normal[end].id,
                                                               sharpIDs: normal[...end].map(\.id)))
            }
        }
        return state
    }
}
