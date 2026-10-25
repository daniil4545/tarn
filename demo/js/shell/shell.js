// The zsh stand-in. Pure over its arguments: no DOM, no engine, so Node tests drive it.
// createShell({vfs, emit, write, clock, identity, history, cols, sessions, paneId})
//   write(data)       bytes for the terminal
//   emit(name, data)  cwd, prompt, command, exit, viewer.open, tab.new, hook
//   input(data)       bytes from the terminal
import { crlf } from "./ansi.js";
import { createEditor } from "./line-editor.js";
import { createCompleter } from "./completion.js";
import { parseLine } from "./parse.js";
import { buildPrompt, tilde } from "./prompt.js";
import { COMMANDS, COMMAND_NAMES } from "../commands/index.js";

const BRACKETED_PASTE_ON = "\x1b[?2004h";
const BRACKETED_PASTE_OFF = "\x1b[?2004l";
const CLEAR = "\x1b[H\x1b[2J";

export function createShell({ vfs, emit, write, clock, identity, history, cols, sessions, paneId }) {
  let cwd = identity.start;
  let previous = cwd;
  let job = null;
  let exited = false;
  let startedAt = 0;
  let name = "";
  const timers = new Set();

  const env = () => ({ HOME: identity.home, USER: identity.user, PWD: cwd, OLDPWD: previous, SHELL: "/bin/zsh", TERM: "xterm-ghostty" });

  const editor = createEditor({
    write,
    cols,
    history,
    complete: createCompleter({ vfs, cwd: () => cwd, home: identity.home, commands: COMMAND_NAMES }),
    on: {
      line: run,
      interrupt: prompt,
      eof() { write("exit\r\n"); exit(); },
      clear() { clear(false); },
    },
  });

  function prompt() {
    write(BRACKETED_PASTE_ON);
    editor.begin(buildPrompt({ identity, cwd, branch: vfs.gitBranch(cwd) }));
    emit("prompt", {});
  }

  // Clears the screen and draws the prompt again with the text typed so far.
  function clear(withScrollback) {
    write(withScrollback ? `${CLEAR}\x1b[3J` : CLEAR);
    emit("prompt-reset", {});
    editor.redraw();
    emit("prompt", {});
  }

  function exit() {
    exited = true;
    write(BRACKETED_PASTE_OFF);
    emit("exit", {});
  }

  function finish() {
    for (const id of timers) clock.cancel(id);
    timers.clear();
    job = null;
    emit("command", { name, ms: clock.now() - startedAt });
    if (!exited) prompt();
  }

  const ctx = {
    paneId,
    vfs,
    identity,
    emit,
    write,
    cols,
    sessions,
    now: clock.now,
    env,
    out: (s) => write(crlf(`${s}\n`)),
    get cwd() { return cwd; },
    cd(path) { previous = cwd; cwd = path; emit("cwd", { cwd: tilde(cwd, identity.home) }); },
    get previous() { return previous; },
    exit,
    clearScreen() { write(`${CLEAR}\x1b[3J`); emit("prompt-reset", {}); },
    after(ms, fn) {
      const id = clock.after(ms, () => { timers.delete(id); fn(); });
      timers.add(id);
      return id;
    },
    cancel(id) {
      clock.cancel(id);
      timers.delete(id);
    },
    // Keeps the command running after its function returned; the result is `done(code)`.
    hold(handlers) {
      job = handlers;
      return finish;
    },
  };

  function run(line) {
    write(BRACKETED_PASTE_OFF);
    if (!line.trim()) return prompt();
    const { words, error } = parseLine(line, env());
    if (error) {
      ctx.out(`zsh: ${error}`);
      return prompt();
    }
    const command = COMMANDS[words[0]];
    if (!command) {
      ctx.out(`zsh: command not found: ${words[0]}`);
      return prompt();
    }
    name = words[0];
    startedAt = clock.now();
    try {
      command({ ...ctx, args: words.slice(1) });
    } catch (e) {
      console.warn(`tarn-demo: ${paneId}: ${name}:`, e);
      ctx.out(`tarn-demo: ${name}: internal error`);
    }
    if (!job) finish();
  }

  return {
    get cwd() { return cwd; },
    get busy() { return job ? name : null; },
    // Shows the first prompt; `resume` re-enters a running claude session without its banner.
    start({ resume = false } = {}) {
      if (resume) run("claude --continue");
      else prompt();
    },
    input(data) {
      if (exited) return;
      if (!job) return editor.input(data);
      if (job.input) return job.input(data);
      if (data.includes("\x03")) {
        write("^C\r\n");
        job.cancel?.();
        finish();
      }
    },
    answer(allow) { job?.answer?.(allow); },
    clear(withScrollback) { if (!job) clear(withScrollback); },
    dispose() {
      for (const id of timers) clock.cancel(id);
      timers.clear();
      job?.cancel?.();
    },
  };
}
