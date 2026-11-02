import CoreGraphics

/// Recognises a quick back-and-forth "shake" of the cursor.
///
/// A shake is a number of direction reversals on one axis inside a short time window,
/// where each stroke between reversals travels far enough to rule out hand jitter.
public struct ShakeDetector: Sendable {

    private struct Axis: Sendable {
        var direction = 0
        var travel: CGFloat = 0
        var reversals: [Double] = []
    }

    /// 0 = needs a big, vigorous shake; 1 = a small wiggle is enough.
    public var sensitivity: Double {
        didSet { sensitivity = min(max(sensitivity, 0), 1) }
    }
    /// Seconds in which the reversals must happen.
    public var window: Double = 0.75
    /// Seconds after a shake during which no new shake is reported.
    public var cooldown: Double = 1.0
    /// A pause longer than this resets the gesture.
    public var idleReset: Double = 0.25

    private var axes = [Axis(), Axis()]
    private var lastPoint: CGPoint?
    private var lastTime: Double?
    private var lastFire = -Double.infinity

    public init(sensitivity: Double = 0.5) {
        self.sensitivity = min(max(sensitivity, 0), 1)
    }

    /// Minimum stroke length in points between two reversals.
    public var minimumStroke: CGFloat { CGFloat(90 - 60 * sensitivity) }
    /// Reversals needed inside `window`.
    public var requiredReversals: Int { Int((5 - 2 * sensitivity).rounded()) }

    /// Feed a cursor sample. Returns `true` exactly once per recognised shake.
    public mutating func feed(_ point: CGPoint, at time: Double) -> Bool {
        defer { lastPoint = point; lastTime = time }
        guard let previous = lastPoint, let previousTime = lastTime else { return false }
        if time - previousTime > idleReset { reset(); return false }

        let deltas = [point.x - previous.x, point.y - previous.y]
        for index in 0..<2 {
            let delta = deltas[index]
            guard abs(delta) >= 0.5 else { continue }
            let sign = delta > 0 ? 1 : -1
            var axis = axes[index]
            if axis.direction == 0 || axis.direction == sign {
                axis.travel += abs(delta)
            } else {
                if axis.travel >= minimumStroke { axis.reversals.append(time) }
                axis.travel = abs(delta)
            }
            axis.direction = sign
            axis.reversals.removeAll { time - $0 > window }
            axes[index] = axis

            if axis.reversals.count >= requiredReversals {
                reset()
                guard time - lastFire >= cooldown else { return false }
                lastFire = time
                return true
            }
        }
        return false
    }

    public mutating func reset() {
        axes = [Axis(), Axis()]
    }
}
