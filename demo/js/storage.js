// Versioned localStorage. A bad version or bad JSON gives the seed and a toast; no storage still works.
import { bus } from "./bus.js";

const PREFIX = "tarn-demo-v1:";

export function load(part, seed) {
  try {
    const raw = localStorage.getItem(PREFIX + part);
    if (raw === null) return seed;
    return JSON.parse(raw);
  } catch (e) {
    bus.emit("toast", { text: `Saved ${part} could not be read, starting fresh` });
    return seed;
  }
}

export function save(part, value) {
  try {
    localStorage.setItem(PREFIX + part, JSON.stringify(value));
  } catch (e) {
    console.warn("tarn-demo: storage unavailable", e);
  }
}

export function drop(part) {
  try {
    localStorage.removeItem(PREFIX + part);
  } catch (e) {
    console.warn("tarn-demo: storage unavailable", e);
  }
}

export function clearAll() {
  try {
    for (const key of Object.keys(localStorage)) if (key.startsWith(PREFIX)) localStorage.removeItem(key);
  } catch (e) {
    console.warn("tarn-demo: storage unavailable", e);
  }
}
