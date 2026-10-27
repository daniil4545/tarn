import Foundation

/// A window's copy of its workspace set, as stored in the restorable state under
/// `tarn.workspaces` (`docs/modules/workspaces.md`). Every tab window of a
/// set carries the whole table plus its own key.
struct WorkspaceSnapshot: Codable, Equatable {
    static let version = 1

    struct Entry: Codable, Equatable {
        var id: UUID
        var name: String
        var collapsed: Bool
        /// Missing in snapshots saved before folders; decodes as nil.
        var folder: String?
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
    /// Tabs placed by hand (D22). Missing in snapshots saved before marks; decodes as empty.
    var manual: [TabKey] = []

    /// The set this snapshot describes. A tab listed twice stays in the first workspace;
    /// a workspace without a tab is dropped. A "~" saved with the home folder loads without it,
    /// as every "~" is now.
    func makeSet(home: String = NSHomeDirectory()) -> WorkspaceSet {
        let homeFolder = WorkspaceFolder.standardized(home) ?? home
        var members: [TabKey: Workspace.ID] = [:]
        var kept: [Workspace] = []
        for entry in workspaces {
            var any = false
            for key in entry.tabKeys where members[key] == nil {
                members[key] = entry.id
                any = true
            }
            let folder = entry.name == WorkspaceSet.homeName && entry.folder == homeFolder ? nil : entry.folder
            if any { kept.append(Workspace(id: entry.id, name: entry.name, collapsed: entry.collapsed, folder: folder)) }
        }
        return WorkspaceSet(id: setID, workspaces: kept, members: members, manual: Set(manual), revision: revision)
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
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        setID = try container.decode(UUID.self, forKey: .setID)
        revision = try container.decode(Int.self, forKey: .revision)
        tabKey = try container.decode(TabKey.self, forKey: .tabKey)
        workspaces = try container.decode([Entry].self, forKey: .workspaces)
        manual = try container.decodeIfPresent([TabKey].self, forKey: .manual) ?? []
    }

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
                folder: run.workspace.folder,
                tabKeys: run.tabs + extra.sorted { $0.uuidString < $1.uuidString }
            )
        }
        for workspace in set.workspaces where !shown.contains(workspace.id) {
            let keys = set.tabs(in: workspace.id).sorted { $0.uuidString < $1.uuidString }
            if !keys.isEmpty {
                entries.append(Entry(
                    id: workspace.id, name: workspace.name, collapsed: workspace.collapsed, folder: workspace.folder, tabKeys: keys
                ))
            }
        }
        self.workspaces = entries
        self.manual = set.manual.sorted { $0.uuidString < $1.uuidString }
    }
}
