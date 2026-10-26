import SwiftUI

/// The durations and curves of tarn's own animations, so they share one rhythm. Ghostty's
/// overlays use 0.15 to 0.4 s with no common token (`R-anim`, T-151); ours stay in the lower
/// half of that range. A sidebar animation takes its timing from here, never a literal.
enum Motion {
    /// A pointer enters or leaves a control: a hover fill, a button highlight.
    static let fast: Double = 0.1

    /// A part of the layout appears or folds: a workspace folds its rows.
    static let base: Double = 0.15

    static var hover: Animation { .easeOut(duration: fast) }

    static var fold: Animation { .easeInOut(duration: base) }
}
