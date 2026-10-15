import Foundation
#if os(iOS)
import CoreHaptics
import UIKit
#endif

/// The app's taps, matched to Android's: a light tick for a step or an undo, and for marking
/// something done a firm click and two fading ticks, like a box snapping shut.
@MainActor
public enum Haptics {
    #if os(iOS)
    private static var engine: CHHapticEngine? = {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return nil }
        let e = try? CHHapticEngine()
        e?.isAutoShutdownEnabled = true
        e?.resetHandler = { try? Haptics.engine?.start() }
        return e
    }()

    /// Android: PRIMITIVE_CLICK 1.0, TICK 0.6 after 60 ms, TICK 0.3 after another 50 ms.
    private static let snap: CHHapticPattern? = try? CHHapticPattern(events: [
        (0.0, 1.0, 0.7), (0.06, 0.6, 0.9), (0.11, 0.3, 0.9),
    ].map { at, intensity, sharpness in
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity)),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(sharpness)),
        ], relativeTime: at)
    }, parameters: [])
    #endif

    public static func done() {
        #if os(iOS)
        if let engine, let snap, (try? engine.start()) != nil, let player = try? engine.makePlayer(with: snap), (try? player.start(atTime: 0)) != nil { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    /// A step toward the day's count, or a switch.
    public static func tick() {
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    /// Undoing a done check.
    public static func undo() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}
