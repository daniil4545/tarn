import SwiftUI

/// The durations and curves of tarn's own animations, one rhythm. A sidebar animation takes its
/// timing from here, never a literal.
enum Motion {
    /// A pointer enters or leaves a control: a hover fill, a button highlight.
    static let fast: Double = 0.1

    /// A part of the layout appears or folds: a workspace folds its rows.
    static let base: Double = 0.15

    static var hover: Animation { .easeOut(duration: fast) }

    static var fold: Animation { .easeInOut(duration: base) }

    /// The rows part for a dragged tab: short and without a slow start, so they keep up with the pointer.
    static var gap: Animation { .easeOut(duration: fast) }
}
