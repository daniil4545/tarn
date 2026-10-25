import Foundation

/// A window's copy of its workspace set, as stored in the restorable state under
/// `tarn.workspaces` (`docs/plans/s3-windows-contracts.md` section 9). Every tab window of a
/// set carries the whole table plus its own key.
struct WorkspaceSnapshot: Codable, Equatable {
    static let version = 1

    struct Entry: Codable, Equatable {
        var id: UUID
        var name: String
        var collapsed: Bool
        /// In tab order.
        var tabKeys: [TabKey]
    }

    enum DecodeError: Error, Equatable {
        case unknownVersion(Int)
    }

    var version = Self.version
    var setID: UUID
    var revision: Int
    /// The window this copy was saved from.
    var tabKey: TabKey
    /// In run order.
    var workspaces: [Entry]

    /// The set this snapshot describes. A tab listed twice stays in the first workspace;
    /// a workspace without a tab is dropped (D12).
    func makeSet() -> WorkspaceSet {
        var members: [TabKey: Workspace.ID] = [:]
        var kept: [Workspace] = []
        for entry in workspaces {
            var any = false
            for key in entry.tabKeys where members[key] == nil {
                members[key] = entry.id
                any = true
            }
            if any { kept.append(Workspace(id: entry.id, name: entry.name, collapsed: entry.collapsed)) }
        }
        return WorkspaceSet(id: setID, workspaces: kept, members: members, revision: revision)
    }

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    static func decode(_ data: Data) throws -> WorkspaceSnapshot {
        struct Header: Decodable { let version: Int }
        let header = try JSONDecoder().decode(Header.self, from: data)
        guard header.version == version else { throw DecodeError.unknownVersion(header.version) }
        return try JSONDecoder().decode(WorkspaceSnapshot.self, from: data)
    }
}

extension WorkspaceSnapshot {
    /// `order` is the native tab order of the window's group. Members that are not in it
    /// (a window still being restored) follow their workspace's live tabs.
    init(set: WorkspaceSet, tabKey: TabKey, order: [TabKey]) {
        self.setID = set.id
        self.revision = set.revision
        self.tabKey = tabKey

        let runs = set.runs(order: order)
        let shown = Set(runs.map(\.workspace.id))
        var entries = runs.map { run -> Entry in
            let extra = set.tabs(in: run.workspace.id).filter { !run.tabs.contains($0) }
            return Entry(
                id: run.workspace.id,
                name: run.workspace.name,
                collapsed: run.workspace.collapsed,
                tabKeys: run.tabs + extra.sorted { $0.uuidString < $1.uuidString }
            )
        }
        for workspace in set.workspaces where !shown.contains(workspace.id) {
            let keys = set.tabs(in: workspace.id).sorted { $0.uuidString < $1.uuidString }
            if !keys.isEmpty {
                entries.append(Entry(id: workspace.id, name: workspace.name, collapsed: workspace.collapsed, tabKeys: keys))
            }
        }
        self.workspaces = entries
    }
}
