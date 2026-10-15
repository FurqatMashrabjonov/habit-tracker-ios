import SwiftUI

/// A whole number that counts through every value in between when it changes under an animation
/// (Android's countUp: 0 → value on first show, then glides).
public struct CountingText: View, Animatable {
    public var value: Double
    public init(_ value: Double) { self.value = value }
    nonisolated public var animatableData: Double { get { value } set { value = newValue } }
    public var body: some View { Text("\(Int(value.rounded()))").monospacedDigit() }
}
