// window.__tarn: the only way tests read state (demo/js/CONTRACT.md).
// Read only. Modules that own a view fill `hooks` with their reader.
import { errors } from "./bus.js";
import { snapshot } from "./state.js";
import { clock } from "./clock.js";

const missing = (name) => () => { throw new Error(`test hook not set: ${name}`); };

export const hooks = {
  screen: missing("screen"), // (paneId) -> text of the screen, rows joined by \n
  linkAt: missing("linkAt"), // (paneId, text) -> {x, y} page position of the first match, or null
  term: missing("term"), // (paneId) -> { options }
  viewer: missing("viewer"), // () -> viewer state
};

export function installTestContract() {
  window.__tarn = Object.freeze({
    snapshot,
    screen: (id) => hooks.screen(id),
    linkAt: (id, text) => hooks.linkAt(id, text),
    term: (id) => hooks.term(id),
    viewer: () => ({ state: () => hooks.viewer() }),
    clock: Object.freeze({ freeze: clock.freeze, advance: clock.advance }),
    errors,
    requests: () => performance.getEntriesByType("resource").map((r) => r.name),
  });
}
