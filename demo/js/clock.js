// Time source of the demo. Real by default; a test calls freeze() before it starts a script,
// then drives timers with advance(). Timers created before freeze() stay real.
let manual = false;
let time = 0;
let nextId = 1;
const timers = new Map();

export const clock = {
  now: () => (manual ? time : Date.now()),

  after(ms, fn) {
    if (!manual) return window.setTimeout(fn, ms);
    const id = nextId++;
    timers.set(id, { at: time + ms, fn });
    return id;
  },

  cancel(id) {
    if (manual) timers.delete(id);
    else window.clearTimeout(id);
  },

  freeze() {
    manual = true;
    time = Date.now();
  },

  advance(ms) {
    const end = time + ms;
    for (;;) {
      const due = [...timers].filter(([, t]) => t.at <= end).sort(([, a], [, b]) => a.at - b.at)[0];
      if (!due) break;
      const [id, timer] = due;
      timers.delete(id);
      time = timer.at;
      timer.fn();
    }
    time = end;
  },
};
