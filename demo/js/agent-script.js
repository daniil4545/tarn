// Scripted Claude Code session behind the `claude` command. It sends the same hook events the
// real plugin does (docs/spec.md section 8) and never sets a state itself: the registry does.
// One turn: spinner, Read, Edit that waits for permission, Read, summary, Stop. A request with
// a question mark gets AskUserQuestion with two questions instead of the Edit.
import { createEditor } from "./shell/line-editor.js";
import { crlf, dim, green } from "./shell/ansi.js";
import { REPO } from "./vfs-seed.js";

const FRAMES = ["✻", "✽", "✶", "✳"];
const SPINNER_MS = 250;
const EDIT_FILE = "docs/spec.md";
const READ_FILE = "README.md";

// The questions of the AskUserQuestion turn, as Claude Code sends them in tool_input.
const QUESTIONS = [
  { question: "Which tab style should the guide show?", header: "Tabs", multiSelect: false, options: [{ label: "Sidebar" }, { label: "Tabs at the top" }] },
  { question: "How wide should sidebar rows be?", header: "Rows", multiSelect: false, options: [{ label: "Wide" }, { label: "Narrow" }] },
];

const yes = /^(y|yes|1)$/i;
const no = /^(n|no|2)$/i;

export function startAgentSession(ctx, { banner }) {
  const { write } = ctx;
  const history = [];
  const mine = new Set();
  let phase = "idle"; // idle: waiting for a request, running, asking: permission pending, choosing: questions pending
  let chosen = []; // answers typed in the terminal so far, one per question
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

  const chooser = createEditor({
    write,
    cols: ctx.cols,
    on: {
      line(text) {
        const q = QUESTIONS[chosen.length], pick = q.options[Number(text.trim()) - 1];
        if (!pick) return chooser.begin(`  Choose 1 or 2: `);
        chosen.push(pick.label);
        if (chosen.length < QUESTIONS.length) return chooser.begin(`  Question ${chosen.length + 1} (1/2): `);
        resolveQuestions(Object.fromEntries(QUESTIONS.map((x, i) => [x.question, chosen[i]])), "terminal");
      },
      interrupt: () => interrupt(),
      eof: () => {},
      clear: () => {},
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
    later(2800, () => (text.includes("?") ? askQuestions(text) : ask(text)));
  }

  function askQuestions(text) {
    phase = "choosing";
    chosen = [];
    pending = text;
    stopSpinner();
    write(crlf(`● AskUserQuestion\n${QUESTIONS.map((q, i) => `  ${i + 1}. ${q.question}  ${q.options.map((o, j) => `${j + 1}) ${o.label}`).join("   ")}`).join("\n")}\n`));
    hook("PermissionRequest", {
      request: { kind: "question", tool: "AskUserQuestion", detail: QUESTIONS[0].question, options: [], questions: QUESTIONS },
      answerable: true,
    });
    chooser.begin(`  Question 1 (1/2): `);
  }

  // Answers: question text to the chosen label, as the hook's updatedInput.answers carries them.
  function resolveQuestions(answers, source) {
    if (phase !== "choosing") return;
    phase = "running";
    if (source === "card") write(`\r\x1b[K  ${dim("answered in the card")}\r\n`);
    startSpinner();
    if (source === "card") hook("PostToolUse");
    later(1000, () => finish(`Got it. ${QUESTIONS.map((q) => `${q.header}: ${answers[q.question]}`).join(", ")}.\nRequest: ${pending}`));
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
      if (phase === "choosing") return chooser.input(data);
      if (data.includes("\x03")) {
        write("^C\r\n");
        interrupt();
      }
      return undefined;
    },
    answer: (value) => (typeof value === "object" ? resolveQuestions(value, "card") : resolve(value, "card")),
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
