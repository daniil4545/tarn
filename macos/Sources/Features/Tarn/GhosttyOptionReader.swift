import Foundation
import GhosttyKit

/// Reads the effective value of a catalog option from a loaded config through `ghostty_config_get`,
/// formatted in file syntax so it compares with `GhosttyOption.defaultValue` and file values.
enum GhosttyOptionReader {
    /// `nil` when Ghostty cannot say: the option is unreadable (`theme`, `font-family`,
    /// `window-padding-x`) or an optional option is unset (`cursor-style-blink`, `macos-option-as-alt`).
    /// A radius or glass `background-blur` reads as "true"; the file keeps the exact text.
    static func value(of option: GhosttyOption, in config: Ghostty.Config) -> String? {
        guard let cfg = config.config else { return nil }
        let key = option.key
        let length = UInt(key.utf8.count)
        switch option.reading {
        case .unreadable:
            return nil
        case .bool:
            var v = false
            return ghostty_config_get(cfg, &v, key, length) ? String(v) : nil
        case .float32:
            var v: Float = 0
            return ghostty_config_get(cfg, &v, key, length) ? Double(v).optionText : nil
        case .float64:
            var v: Double = 0
            return ghostty_config_get(cfg, &v, key, length) ? v.optionText : nil
        case .tag:
            var v: UnsafePointer<Int8>?
            guard ghostty_config_get(cfg, &v, key, length), let v else { return nil }
            return String(cString: v)
        case .blur:
            var v: Int16 = 0
            return ghostty_config_get(cfg, &v, key, length) ? String(v != 0) : nil
        case .duration:
            var v: UInt = 0
            guard ghostty_config_get(cfg, &v, key, length) else { return nil }
            return v % 1000 == 0 ? "\(v / 1000)s" : "\(v)ms"
        }
    }
}
