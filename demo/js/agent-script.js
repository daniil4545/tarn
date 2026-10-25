// Scripted Claude Code session behind the `claude` command. It sends the same hook events the
// real plugin does (docs/spec.md section 8) and never sets a state itself: the registry does.
// One turn: spinner, Read, Edit that waits for permission, Read, summary, Stop.
import { createEditor } from "./shell/line-editor.js";
import { crlf, dim, green } from "./shell/ansi.js";
import { REPO } from "./vfs-seed.js";

const FRAMES = ["✻", "✽", "✶", "✳"];
const SPINNER_MS = 250;
const EDIT_FILE = "docs/spec.md";
const READ_FILE = "README.md";

const yes = /^(y|yes|1)$/i;
const no = /^(n|no|2)$/i;

export function startAgentSession(ctx, { banner }) {
  const { write } = ctx;
  const history = [];
  const mine = new Set();
  let phase = "idle"; // idle: waiting for a request, running, asking: permission pending
  let spinning = false;
  let frame = 0;
  let turns = 0;
  let pending = ""; // the request the edit belongs to

  const root = ctx.vfs.gitRoot(ctx.cwd) ?? REPO;
  const editPath = `${root}/${EDIT_FILE}`;
  const show = (path) => (path.startsWith(`${ctx.cwd}/`) ? path.slice(ctx.cwd.length + 1) : path);
  const hook = (name, event = {}) => ctx.emit("hook", { name, event });

  const later = (ms, fn) => {
    const id = ctx.after(ms, () => { mine.delete(id); fn(); });
    mine.add(id);
  };
  const cancelTimers = () => {
    mine.forEach((id) => ctx.cancel(id));
    mine.clear();
  };

  const spinnerLine = () => dim(`${FRAMES[frame % FRAMES.length]} Working… (esc to interrupt)`);

  // Prints a line above the spinner so the spinner stays the last line.
  function say(text) {
    write(`${spinning ? "\r\x1b[K" : ""}${crlf(text)}\r\n${spinning ? spinnerLine() : ""}`);
  }

  function startSpinner() {
    spinning = true;
    write(spinnerLine());
    const tick = () => {
      if (!spinning) return;
      frame++;
      write(`\r\x1b[K${spinnerLine()}`);
      later(SPINNER_MS, tick);
    };
    later(SPINNER_MS, tick);
  }

  function stopSpinner() {
    if (spinning) write("\r\x1b[K");
    spinning = false;
  }

  const tool = (name, path) => say(`● ${name}(${show(path)})`);

  const editor = createEditor({
    write,
    cols: ctx.cols,
    history,
    on: {
      line(text) {
        const line = text.trim();
        if (line === "/exit" || line === "/quit") leave();
        else if (line) request(line);
        else editor.begin(green("> "));
      },
      interrupt: () => editor.begin(green("> ")),
      eof: () => leave(),
      clear: () => {
        write("\x1b[H\x1b[2J");
        editor.redraw();
      },
    },
  });

  const asker = createEditor({
    write,
    cols: ctx.cols,
    on: {
      line(text) {
        if (yes.test(text.trim())) resolve(true, "terminal");
        else if (no.test(text.trim())) resolve(false, "terminal");
        else asker.begin("  Choose y or n: ");
      },
      interrupt: () => interrupt(),
      eof: () => {},
      clear: () => {},
    },
  });

  function request(text) {
    phase = "running";
    turns++;
    hook("UserPromptSubmit");
    startSpinner();
    later(1200, () => tool("Read", `${root}/${READ_FILE}`));
    later(1800, () => hook("PostToolUse"));
    later(2800, () => ask(text));
  }

  function ask(text) {
    phase = "asking";
    stopSpinner();
    write(crlf(`● Update(${show(editPath)})\n  Do you want to make this edit to ${show(editPath)}?\n  1. Yes   2. No\n`));
    hook("PermissionRequest", {
      request: { kind: "tool", tool: "Edit", detail: show(editPath), options: [] },
      answerable: true,
    });
    asker.begin("  Choose (y/n): ");
    pending = text;
  }

  // The card answers with a hook decision; typing in the pane sends no event (spec section 8, known limit).
  function resolve(allow, source) {
    if (phase !== "asking") return;
    phase = "running";
    if (source === "card") write(`\r\x1b[K  ${dim("answered in the card")}\r\n`);
    startSpinner();
    if (!allow) {
      say("  ⎿ Rejected");
      later(800, () => finish(`Understood. I left ${show(editPath)} unchanged.`));
      return;
    }
    // A missing file or folder must not stop the session before its Stop event.
    let note;
    try {
      const text = ctx.vfs.exists(editPath) ? ctx.vfs.read(editPath) : "";
      ctx.vfs.write(editPath, `${text}${text.endsWith("\n") || !text ? "" : "\n"}\nDemo edit ${turns}: reviewed by claude.\n`, "claude");
      note = `  ⎿ Updated ${show(editPath)}`;
    } catch (e) {
      note = `  ⎿ Could not update ${show(editPath)}: ${e.code ?? e.message}`;
    }
    say(note);
    if (source === "card") hook("PostToolUse");
    later(1200, () => tool("Read", `${root}/${READ_FILE}`));
    later(1800, () => hook("PostToolUse"));
    later(2800, () => finish(`Done. Request: ${pending}\nChanges:\n- ${show(editPath)}: demo note added`));
  }

  function finish(summary) {
    stopSpinner();
    write(`${crlf(summary)}\r\n\r\n`);
    hook("Stop");
    phase = "idle";
    editor.begin(green("> "));
  }

  function interrupt() {
    cancelTimers();
    stopSpinner();
    write(`${crlf("  ⎿ Interrupted by user")}\r\n`);
    hook("Stop");
    phase = "idle";
    editor.begin(green("> "));
  }

  const done = ctx.hold({
    input(data) {
      if (phase === "idle") return editor.input(data);
      if (phase === "asking") return asker.input(data);
      if (data.includes("\x03")) {
        write("^C\r\n");
        interrupt();
      }
      return undefined;
    },
    answer: (allow) => resolve(allow, "card"),
    cancel: cancelTimers,
  });

  function leave() {
    write(`${crlf("Goodbye!")}\r\n`);
    hook("SessionEnd", { reason: "prompt_input_exit" });
    done(0);
  }

  if (banner) write(crlf(`${dim("╭─ Claude Code ─────────────────────────╮")}\n${dim("  Type a request and press Enter. /exit or Ctrl-D leaves.")}\n`));
  editor.begin(green("> "));
}
