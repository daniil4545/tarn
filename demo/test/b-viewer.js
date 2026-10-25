// Stand-in for the viewer of slice C: a pane with a file tab bar. Its tabs carry data-drag, and it
// answers viewer.open, viewer.take and viewer.merge as the real viewer does.
import { bus } from "../js/bus.js";

const viewers = new Map(); // id -> {el, files}

function draw(id) {
  const { el, files } = viewers.get(id);
  const tab = (path, idx) => `<div class="ftab" draggable="true" data-drag='${JSON.stringify({ kind: "file", path, from: id, idx })}'>${path}</div>`;
  el.innerHTML = `<div class="vh">${files.map(tab).join("")}</div><div class="scroll"></div>`;
}

export function createViewer(id) {
  const el = Object.assign(document.createElement("div"), { className: "vstub", tabIndex: 0 });
  el.dataset.pane = id;
  viewers.set(id, { el, files: [] });
  draw(id);
  return {
    id,
    el,
    focus: () => el.focus(),
    dispose() {
      el.remove();
      viewers.delete(id);
      bus.emit("pane:disposed", { pane: id });
    },
  };
}

function add(id, path) {
  const { files } = viewers.get(id);
  if (!files.includes(path)) files.push(path);
  draw(id);
}

export function startViewerStub() {
  bus.handle("viewer.open", ({ path, pane }) => {
    const id = pane ?? [...viewers].find(([, v]) => v.el.offsetParent !== null)?.[0];
    if (!id) return bus.emit("viewer:needed", { path });
    add(id, path);
  });
  bus.handle("viewer.take", ({ to, drag }) => {
    const from = viewers.get(drag.from);
    from.files.splice(drag.idx, 1);
    add(to, drag.path);
    if (!from.files.length && drag.from !== to) bus.cmd("pane.close", { id: drag.from });
    else draw(drag.from);
  });
  bus.handle("viewer.merge", ({ from, to }) => {
    viewers.get(from).files.forEach((path) => add(to, path));
    bus.cmd("pane.close", { id: from });
  });
}
