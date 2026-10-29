// Start state of the demo; ids t1 and w1 are kept from the mockup for the ported checks.
// A tab's `layout` is a tree owned by workspace.js; the seed holds one pane per tab.
export const WORKSPACES = {
  tabs: {
    t1: { id: "t1", title: "Claude · spec", cwd: "~/code/tarn", layout: { pane: "p1" } },
    t2: { id: "t2", title: "Claude · review", cwd: "~/code", layout: { pane: "p2" } },
    t3: { id: "t3", title: "git · tarn", cwd: "~/code/tarn", layout: { pane: "p3" } },
    t4: { id: "t4", title: "ssh staging", cwd: "root@staging:~", layout: { pane: "p4" } },
    t5: { id: "t5", title: "Claude · website", cwd: "~/code/website", layout: { pane: "p5" } },
    t6: { id: "t6", title: "~", cwd: "~", layout: { pane: "p6" } },
  },
  wss: [
    { id: "w1", name: "tarn", folder: "~/code/tarn", tabs: ["t1", "t2", "t3", "t4"] },
    { id: "w2", name: "release", tabs: ["t5"] },
    { id: "w0", name: "", loose: true, tabs: ["t6"] },
  ],
  cur: "t1",
};

// Sessions by pane id. t1 ended its turn and was not looked at: waiting and not seen.
export const SESSIONS = {
  p1: { state: "waiting", seen: false, failed: false },
  p2: { state: "working", seen: true, failed: false },
  p5: { state: "working", seen: true, failed: false },
};
