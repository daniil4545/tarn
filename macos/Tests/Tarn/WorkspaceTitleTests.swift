import Testing
@testable import Ghostty

/// Q4, Q10, D14: the workspace name is the window subtitle, only with the sidebar style.
@Suite
struct WorkspaceTitleTests {
    @Test func theSubtitleIsTheWorkspaceNameWithTheSidebar() {
        #expect(WorkspaceTitle.subtitle(workspace: "Work", style: .sidebar) == "Work")
        #expect(WorkspaceTitle.subtitle(workspace: nil, style: .sidebar) == "")
    }

    @Test func theTopTabBarShowsNoWorkspace() {
        #expect(WorkspaceTitle.subtitle(workspace: "Work", style: .top) == "")
    }

    @Test func theSettingsTextNamesWorkspaces() {
        #expect(TabStyle.sidebar.detail.hasPrefix("Tabs grouped in workspaces"))
    }
}
