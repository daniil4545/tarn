import Testing
@testable import Ghostty

/// The workspace name is the window subtitle, whatever the tab style.
@Suite
struct WorkspaceTitleTests {
    // spec: docs/specs/workspace-folder.md S23
    @Test func theSubtitleIsTheWorkspaceName() {
        #expect(WorkspaceTitle.subtitle(workspace: "Work") == "Work")
        #expect(WorkspaceTitle.subtitle(workspace: nil) == "")
    }

    // spec: docs/specs/workspace-folder.md S23
    // Tabs at the top: the tab mark carries the workspace name; an ungrouped tab (name empty) has none.
    @Test func theNativeTabMarkNamesTheWorkspace() {
        #expect(NativeTabMark.workspaceName("Work", workspaces: 2) == "Work")
        #expect(NativeTabMark.workspaceName("Work", workspaces: 1) == nil)
        #expect(NativeTabMark.workspaceName("", workspaces: 2) == nil)
    }
}
