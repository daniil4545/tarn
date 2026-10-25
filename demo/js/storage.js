// Versioned localStorage. Bad JSON or a wrong shape gives the seed and a toast; no storage still works.
import { bus } from "./bus.js";

const PREFIX = "tarn-demo-v1:";

// isValid checks the parsed shape: a value of the wrong shape is as bad as broken JSON.
export function load(part, seed, isValid = () => true) {
  try {
    const raw = localStorage.getItem(PREFIX + part);
    if (raw === null) return seed;
    const value = JSON.parse(raw);
    if (!isValid(value)) throw new Error("unexpected shape");
    return value;
  } catch (e) {
    bus.emit("toast", { text: `Saved ${part} could not be read, starting fresh` });
    return seed;
  }
}

export const isObject = (v) => v !== null && typeof v === "object" && !Array.isArray(v);

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
