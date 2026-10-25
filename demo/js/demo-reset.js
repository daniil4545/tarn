// "Reset demo": forget everything the demo stored in this browser and start from the seed.
import { bus } from "./bus.js";
import { clearAll } from "./storage.js";

// A palette entry; Settings (Windows) has a button for the same command.
export const RESET_ROW = { id: "demo.reset", group: "Demo", text: "Reset demo", chords: [], cmd: "demo.reset" };

export function startDemoReset() {
  bus.handle("demo.reset", () => {
    clearAll();
    location.reload();
  });
}
