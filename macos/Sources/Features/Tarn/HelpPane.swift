import SwiftUI

/// The Help section of the settings window: the keys in effect, read from the live Ghostty config.
struct HelpPane: View {
    /// The store already follows the app's config notification.
    @ObservedObject private var store: GhosttyOptionStore = .shared

    var body: some View {
        Form {
            ForEach(KeyReference.groups) { group in
                Section(group.title) {
                    ForEach(group.rows) { row in
                        let keys = KeyReference.keys(for: row, in: store.config)
                        LabeledContent {
                            HStack {
                                Text(keys)
                                    .font(.body.monospaced())
                                    .foregroundStyle(keys == KeyReference.notBound ? .secondary : .primary)
                                    .frame(minWidth: 70, alignment: .trailing)
                                Text(row.source)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 50, alignment: .leading)
                            }
                        } label: {
                            Text(row.label)
                        }
                    }
                }
            }
            Section {
                Text("Ghostty defaults. A keybind line in the Ghostty config changes them, and Help shows the keys in effect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Help")
    }
}
