import SwiftUI

/// The theme control of the Appearance section: the base themes on top with a sample each, then
/// every installed theme with a filter. One theme is chosen; there is no light and dark pair.
/// The sample is the theme's background, text and four palette colors, read from its file.
struct ThemePicker: View {
    /// The chosen theme; `""` is the default entry; `nil` when the Ghostty config decides.
    let current: String?
    let pick: (String) -> Void

    @State private var filter = ""

    /// Read once per process: the row is rebuilt on each write. A theme added later shows after a restart.
    private static let names = ThemeCatalog.shared.names
    private static let base = ThemeCatalog.shared.base(among: names)
    private static let rest = ThemeCatalog.shared.rest(among: names)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Base themes").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                if showsDefault { ThemeRow(name: "", chosen: current == "", pick: pick) }
                ForEach(ThemeCatalog.matching(Self.base, query: filter), id: \.self) { name in
                    ThemeRow(name: name, chosen: current == name, pick: pick)
                }
            }
            HStack {
                Text("All themes").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("\(Self.rest.count)").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.top, 4)
            TextField("Filter themes", text: $filter)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Filter themes")
            ScrollView {
                if shown.isEmpty && !showsDefault && ThemeCatalog.matching(Self.base, query: filter).isEmpty {
                    Text("No themes match").font(.caption).foregroundStyle(.secondary).padding(8)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 2) {
                    ForEach(shown, id: \.self) { name in
                        ThemeRow(name: name, chosen: current == name, pick: pick)
                    }
                }
                .padding(4)
            }
            .frame(height: 190)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
        }
        .padding(.top, 4)
    }

    private var shown: [String] { ThemeCatalog.matching(Self.rest, query: filter) }

    /// The default entry stays while the filter is empty or says "default".
    private var showsDefault: Bool { ThemeCatalog.matching(["default"], query: filter).count == 1 }
}

/// A theme as a button: sample, name, and whether it is light or dark.
private struct ThemeRow: View {
    let name: String
    let chosen: Bool
    let pick: (String) -> Void

    private var palette: ThemePalette? { name.isEmpty ? nil : ThemeSamples.palette(of: name) }

    var body: some View {
        Button { pick(name) } label: {
            HStack(spacing: 8) {
                ThemeSample(palette: palette)
                Text(name.isEmpty ? "default" : name).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                if let palette {
                    Text(palette.background.isLight ? "light" : "dark").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(chosen ? Color.accentColor.opacity(0.16) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(chosen ? Color.accentColor : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name.isEmpty ? "default" : name)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// Text on the theme's background and four palette colors: red, green, yellow, blue.
private struct ThemeSample: View {
    let palette: ThemePalette?

    var body: some View {
        HStack(spacing: 6) {
            Text("Aa").font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette?.foreground.color ?? Color.secondary)
            HStack(spacing: 2) {
                ForEach(dots, id: \.self) { Circle().fill($0.color).frame(width: 6, height: 6) }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(width: 74)
        .background(palette?.background.color ?? Color.clear, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
        .accessibilityHidden(true)
    }

    private var dots: [ThemeColor] {
        let slots = [ThemePalette.Slot.red, ThemePalette.Slot.green, ThemePalette.Slot.yellow, ThemePalette.Slot.blue]
        return slots.compactMap { palette?.ansi[$0] }
    }
}

/// Palettes read from theme files once: a scroll shows each row again and again.
@MainActor
private enum ThemeSamples {
    private static var cache: [String: ThemePalette?] = [:]

    static func palette(of name: String) -> ThemePalette? {
        if let hit = cache[name] { return hit }
        let palette = ThemeCatalog.shared.palette(of: name)
        cache[name] = .some(palette)
        return palette
    }
}
