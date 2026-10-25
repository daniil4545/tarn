// One store. Each part has one writer: register() hands the setter to the owner only.
// Everyone else reads frozen snapshots and sends commands on the bus.
import { bus } from "./bus.js";

const parts = new Map();

function freeze(value) {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    Object.values(value).forEach(freeze);
    Object.freeze(value);
  }
  return value;
}

export function register(part, initial) {
  if (parts.has(part)) throw new Error(`part already has a writer: ${part}`);
  parts.set(part, freeze(structuredClone(initial)));
  return (next) => {
    parts.set(part, freeze(structuredClone(next)));
    bus.emit("state:changed", { part });
  };
}

export function read(part) {
  if (!parts.has(part)) throw new Error(`unknown part: ${part}`);
  return parts.get(part);
}

export function snapshot() {
  return Object.freeze(Object.fromEntries(parts));
}
