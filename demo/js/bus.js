// Events and commands between modules. Counterpart of ControlSocket.swift.
const events = new EventTarget();
const handlers = new Map();

export const errors = [];

export const bus = {
  on(event, fn) {
    const listener = (e) => fn(e.detail);
    events.addEventListener(event, listener);
    return () => events.removeEventListener(event, listener);
  },

  emit(event, detail) {
    events.dispatchEvent(new CustomEvent(event, { detail }));
  },

  // A command has exactly one handler, its writer.
  handle(name, fn) {
    if (handlers.has(name)) throw new Error(`command already handled: ${name}`);
    handlers.set(name, fn);
  },

  // Error rule: a failing command warns and toasts, the app lives.
  cmd(name, payload = {}) {
    const fn = handlers.get(name);
    if (!fn) return fail(name, new Error("no handler"));
    try {
      return fn(payload);
    } catch (e) {
      return fail(name, e);
    }
  },
};

function fail(name, error) {
  errors.push(`${name}: ${error.message}`);
  console.warn(`tarn-demo: ${name}:`, error);
  bus.emit("toast", { text: `tarn-demo: ${name}: internal error` });
}
