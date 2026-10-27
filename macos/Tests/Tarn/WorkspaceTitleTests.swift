import Testing
@testable import Ghostty

/// The workspace name is the window subtitle while Workspaces is on, whatever the tab style.
@Suite
struct WorkspaceTitleTests {
    @Test func theSubtitleIsTheWorkspaceNameWhileWorkspacesIsOn() {
        #expect(WorkspaceTitle.subtitle(workspace: "Work", workspacesOn: true) == "Work")
        #expect(WorkspaceTitle.subtitle(workspace: nil, workspacesOn: true) == "")
    }

    @Test func workspacesOffShowsNoWorkspace() {
        #expect(WorkspaceTitle.subtitle(workspace: "Work", workspacesOn: false) == "")
    }

    @Test func theSettingsTextNamesTheTabs() {
        #expect(TabStyle.sidebar.detail.hasPrefix("Tabs with agent state"))
        #expect(TabStyle.top.detail.contains("workspace name"))
    }

    // Tabs at the top: the tab mark carries the workspace name while Workspaces is on.
    @Test func theNativeTabMarkNamesTheWorkspace() {
        #expect(NativeTabMark.workspaceName("Work", workspacesOn: true, workspaces: 2) == "Work")
        #expect(NativeTabMark.workspaceName("Work", workspacesOn: true, workspaces: 1) == nil)
        #expect(NativeTabMark.workspaceName("Work", workspacesOn: false, workspaces: 3) == nil)
        #expect(NativeTabMark.workspaceName("", workspacesOn: true, workspaces: 2) == nil)
    }
}
