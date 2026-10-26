import SwiftUI

/// One settings section of Ghostty options: a row per catalog option.
struct GhosttyOptionsPane: View {
    let section: GhosttyOption.Section
    let title: String
    @ObservedObject var store: GhosttyOptionStore

    var body: some View {
        Form {
            Section {
                ForEach(GhosttyOption.options(in: section)) { option in
                    GhosttyOptionRow(option: option, store: store)
                }
            } footer: {
                footer
            }
        }
        .formStyle(.grouped)
        .navigationTitle(title)
        .onAppear { store.refreshFile() }
    }

    @ViewBuilder private var footer: some View {
        if section == .windows {
            VStack(alignment: .leading, spacing: 6) {
                Text("Written to ~/.config/tarn/ghostty.conf, loaded after your Ghostty config:")
                Text(store.file.text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
        } else {
            Text("Ghostty options. Others, keys included, are in Ghostty Config.")
        }
    }
}

private struct GhosttyOptionRow: View {
    let option: GhosttyOption
    @ObservedObject var store: GhosttyOptionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(option.key).font(.system(.body, design: .monospaced))
                Spacer()
                if store.isSet(option) {
                    Text("set in tarn")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Set here; overrides the same line in the Ghostty config")
                    Button("Reset") { store.reset(option) }
                        .buttonStyle(.borderless)
                }
                control
            }
            Text(option.help).font(.caption).foregroundStyle(.secondary)
            if option.control == .theme { themePicker }
            if let applies = appliesText {
                Text(applies).font(.caption).foregroundStyle(.secondary)
            }
            if let error = store.errors[option.key] {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var themePicker: some View {
        switch store.display(option) {
        case let .value(current):
            ThemePicker(current: current) { store.set(option, to: $0) }
        case .fromGhosttyConfig:
            ThemePicker(current: nil) { store.set(option, to: $0) }
        case .raw:
            EmptyView()
        }
    }

    /// Live options say nothing; the others say when they apply.
    private var appliesText: String? {
        switch option.applies {
        case .live: nil
        case .newWindows: "Applies to new windows."
        case .restart: "Restart needed."
        }
    }

    @ViewBuilder private var control: some View {
        switch store.display(option) {
        case let .raw(text):
            Text(text).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                .help("The file holds a value this control cannot show. Reset gives it back.")
        case let .value(current):
            valueControl(current)
        case .fromGhosttyConfig:
            valueControl(nil)
        }
    }

    /// `current` is nil when Ghostty cannot say and tarn sets nothing.
    @ViewBuilder private func valueControl(_ current: String?) -> some View {
        let binding = Binding(get: { current ?? "" }, set: { store.set(option, to: $0) })
        switch option.control {
        case .toggle:
            Toggle(option.key, isOn: Binding(get: { current == "true" }, set: { store.set(option, to: String($0)) }))
                .labelsHidden()
        case let .choice(values):
            Picker(option.key, selection: binding) {
                ForEach(values, id: \.self) { Text($0.isEmpty ? "default (auto)" : $0).tag($0) }
            }
            .labelsHidden().fixedSize()
        case .theme:
            // The choice is made in the list under the row.
            Text(current.map { $0.isEmpty ? "default" : $0 } ?? GhosttyOptionStore.fromGhosttyConfigText)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        case let .number(range):
            CommittedField(option: option, store: store, text: current, range: range)
        case let .slider(range, step):
            CommittedSlider(
                option: option, store: store,
                value: Double(current ?? "") ?? Double(option.defaultValue) ?? range.lowerBound,
                range: range, step: step
            )
        case .text:
            CommittedField(option: option, store: store, text: current, range: nil)
        }
    }
}

/// A text or number field that writes on Return or when it loses focus, not on every key.
private struct CommittedField: View {
    let option: GhosttyOption
    @ObservedObject var store: GhosttyOptionStore
    let text: String?
    let range: ClosedRange<Double>?

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(option.key, text: $draft, prompt: Text(GhosttyOptionStore.fromGhosttyConfigText))
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .frame(width: 160)
            .focused($focused)
            .onAppear { draft = text ?? "" }
            // The last saved value comes back after a reset, a failed save or a refresh.
            .onChange(of: text) { draft = $0 ?? "" }
            .onChange(of: store.errors[option.key]) { _ in draft = text ?? "" }
            .onSubmit(commit)
            .onChange(of: focused) { if !$0 { commit() } }
    }

    private func commit() {
        let value = draft.trimmingCharacters(in: .whitespaces)
        if value != (text ?? "") { store.set(option, to: value) }
    }
}

/// A slider that writes when the drag ends.
private struct CommittedSlider: View {
    let option: GhosttyOption
    @ObservedObject var store: GhosttyOptionStore
    let value: Double
    let range: ClosedRange<Double>
    let step: Double

    @State private var drag: Double?

    var body: some View {
        HStack {
            Slider(
                value: Binding(get: { drag ?? value }, set: { drag = $0 }),
                in: range, step: step
            ) { editing in
                if !editing, let drag {
                    store.set(option, to: String(format: "%g", drag))
                    self.drag = nil
                }
            }
            .frame(width: 140)
            Text(String(format: "%g", drag ?? value))
                .font(.system(.body, design: .monospaced))
                .frame(width: 40, alignment: .trailing)
        }
    }
}
