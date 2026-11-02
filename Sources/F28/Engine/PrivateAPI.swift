import AppKit
import QuartzCore

/// Thin, failure-tolerant access to the private window-server and Core Animation APIs
/// f/2.8 relies on. Everything is looked up at runtime, so a missing symbol degrades a
/// feature instead of crashing the app.
enum PrivateAPI {
    private typealias MainConnectionFn = @convention(c) () -> Int32
    private typealias SetBlurRadiusFn = @convention(c) (Int32, UInt32, Int32) -> Int32

    /// `RTLD_DEFAULT` on Darwin.
    private static let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)

    private static func symbol<T>(_ name: String, as _: T.Type) -> T? {
        guard let pointer = dlsym(defaultHandle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }

    private static let mainConnection = symbol("CGSMainConnectionID", as: MainConnectionFn.self)
    private static let setBlurRadius = symbol("CGSSetWindowBackgroundBlurRadius", as: SetBlurRadiusFn.self)

    static var hasWindowBlur: Bool { mainConnection != nil && setBlurRadius != nil }
    static var hasBackdropLayer: Bool { NSClassFromString("CABackdropLayer") != nil }
    static var hasFilters: Bool { NSClassFromString("CAFilter") != nil }

    /// Fallback engine: ask the window server to blur whatever is behind `window`.
    @discardableResult
    static func setBackgroundBlur(_ window: NSWindow, radius: CGFloat) -> Bool {
        guard let mainConnection, let setBlurRadius, window.windowNumber > 0 else { return false }
        return setBlurRadius(mainConnection(), UInt32(window.windowNumber), Int32(radius.rounded())) == 0
    }

    /// A Core Animation render-server filter (`CAFilter`), e.g. `gaussianBlur` or `colorSaturate`.
    static func filter(_ type: String, name: String) -> NSObject? {
        guard let cls = NSClassFromString("CAFilter") else { return nil }
        let selector = NSSelectorFromString("filterWithType:")
        let classObject = cls as AnyObject
        guard classObject.responds(to: selector),
              let filter = classObject.perform(selector, with: type)?.takeUnretainedValue() as? NSObject
        else { return nil }
        filter.setValue(name, forKey: "name")
        return filter
    }
}
