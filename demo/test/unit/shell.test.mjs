// Node tests of the simulated shell: no browser, no engine. Run: node --test demo/test/unit
import test from "node:test";
import assert from "node:assert/strict";
import { createShell } from "../../js/shell/shell.js";
import { createVfs, seedDisk } from "../../js/vfs.js";
import { createScreen } from "./vt.mjs";

const HOME = "/Users/you";
const REPO = `${HOME}/code/tarn`;

function fakeClock() {
  let now = 1_000_000;
  let next = 1;
  const timers = new Map();
  return {
    now: () => now,
    after(ms, fn) { const id = next++; timers.set(id, { at: now + ms, fn }); return id; },
    cancel: (id) => timers.delete(id),
    advance(ms) {
      const end = now + ms;
      for (;;) {
        const due = [...timers].filter(([, t]) => t.at <= end).sort(([, a], [, b]) => a.at - b.at)[0];
        if (!due) break;
        timers.delete(due[0]);
        now = due[1].at;
        due[1].fn();
      }
      now = end;
    },
  };
}

function setup({ cols = 100, cwd = REPO, history = [] } = {}) {
  const screen = createScreen(cols);
  const clock = fakeClock();
  const events = [];
  const vfs = createVfs(seedDisk(), { now: clock.now });
  const shell = createShell({
    vfs,
    clock,
    history,
    cols: () => cols,
    write: (d) => screen.write(d),
    emit: (name, data) => events.push([name, data]),
    identity: { user: "you", host: "mac", home: HOME, start: cwd },
    panes: () => [],
    paneId: "p1",
  });
  shell.start();
  const type = (s) => shell.input(s);
  const run = (line) => type(`${line}\r`);
  return { screen, clock, events, vfs, shell, type, run, history };
}

const hooks = (events) => events.filter(([n]) => n === "hook").map(([, d]) => d.name);

test("prompt shows user, host, cwd and git branch", () => {
  const { screen } = setup();
  assert.equal(screen.lines()[0], "you@mac ~/code/tarn (main) %");
});

test("typing, backspace and arrows edit the line", () => {
  const { screen, type, shell } = setup();
  type("echo hllo");
  type("\x1b[D\x1b[D\x1b[D");
  type("e");
  assert.match(screen.lines()[0], /% echo hello$/);
  type("\x7f");
  assert.match(screen.lines()[0], /% echo hllo$/);
  assert.deepEqual(screen.cursor, { x: screen.lines()[0].length - 3, y: 0 });
  assert.equal(shell.busy, null);
});

test("history recalls with up and down and keeps the draft", () => {
  const { screen, run, type } = setup();
  run("pwd");
  run("whoami");
  type("ec");
  type("\x1b[A");
  assert.match(screen.text(), /% whoami$/);
  type("\x1b[A");
  assert.match(screen.text(), /% pwd$/);
  type("\x1b[B\x1b[B");
  assert.match(screen.text(), /% ec$/);
});

test("ctrl keys: A E U K W", () => {
  const { screen, type } = setup();
  type("one two three");
  type("\x17");
  assert.match(screen.lines()[0], /% one two$/);
  type("\x01");
  type("\x0b");
  assert.match(screen.lines()[0], /%$/);
  type("abc\x15");
  assert.match(screen.lines()[0], /%$/);
});

test("ctrl-C abandons the line and draws a fresh prompt", () => {
  const { screen, type } = setup();
  type("garbage\x03");
  const lines = screen.lines();
  assert.equal(lines[0], "you@mac ~/code/tarn (main) % garbage^C");
  assert.match(lines[1], /%$/);
});

test("ctrl-L clears the screen and keeps the typed text", () => {
  const { screen, run, type } = setup();
  run("pwd");
  type("ls do");
  type("\x0c");
  assert.equal(screen.lines()[0], "you@mac ~/code/tarn (main) % ls do");
  assert.equal(screen.lines()[1], "");
});

test("a long line wraps and editing it redraws every row", () => {
  const { screen, type } = setup({ cols: 30 });
  type("x".repeat(40));
  type("\x01");
  type("Y");
  const text = screen.lines().join("\n");
  assert.match(text, /% Y\nxxx/);
  assert.equal(text.match(/x/g).length, 40);
});

test("pasted line breaks become spaces and nothing runs", () => {
  const { screen, type } = setup();
  type("\x1b[200~echo a\necho b\x1b[201~");
  assert.match(screen.lines()[0], /% echo a echo b$/);
});

test("Tab completes a command, a path and lists on a second Tab", () => {
  const { screen, type } = setup();
  type("who\t");
  assert.match(screen.lines()[0], /% whoami$/);
  type("\x15cd mac\t");
  assert.match(screen.lines()[0], /% cd macos\/$/);
  type("\x15ls d\t");
  assert.match(screen.lines()[0], /% ls docs\/$/);
  type("\x15cat READ\t");
  assert.match(screen.lines()[0], /% cat README.md$/);
  type("\x15tarn \t\t");
  assert.match(screen.text(), /open\s+ls\s+new/);
  type("\x15");
  type("c\t\t");
  assert.match(screen.text(), /cat\s+cd\s+claude\s+clear/);
});

test("cd, pwd, ls, cat, mkdir, touch, rm", () => {
  const { screen, run } = setup();
  run("cd docs");
  assert.match(screen.text(), /tarn\/docs \(main\) %$/);
  run("ls");
  assert.match(screen.text(), /architecture\.md\s+plans\s+spec\.md/);
  run("cat nope.md");
  assert.match(screen.text(), /cat: nope\.md: No such file or directory/);
  run("mkdir demo-dir");
  run("touch demo-dir/a.txt");
  run("ls demo-dir");
  assert.match(screen.text(), /\na\.txt/);
  run("rm demo-dir");
  assert.match(screen.text(), /rm: demo-dir: is a directory/);
  run("rm -r demo-dir");
  run("cd /nowhere");
  assert.match(screen.text(), /cd: no such file or directory: \/nowhere/);
  run("cd -");
  assert.match(screen.text(), /tarn \(main\) %$/);
});

test("unknown command and unsupported operators", () => {
  const { screen, run } = setup();
  run("frobnicate");
  assert.match(screen.text(), /zsh: command not found: frobnicate/);
  run("ls | head");
  assert.match(screen.text(), /zsh: not supported in the demo: \|/);
  run('echo "a  b" $HOME ~');
  assert.match(screen.text(), /a {2}b \/Users\/you \/Users\/you/);
});

test("git status follows vfs edits", () => {
  const { screen, run, vfs } = setup();
  run("git status -s");
  assert.match(screen.text(), / M docs\/spec\.md/);
  vfs.write(`${REPO}/new.txt`, "x");
  run("git status -s");
  assert.match(screen.text(), /\?\? new\.txt/);
  run("git branch");
  assert.match(screen.text(), /\* main/);
  run("cd ~");
  run("git status");
  assert.match(screen.text(), /not a git repository/);
});

test("tarn open emits viewer.open and reports a missing file", () => {
  const { screen, run, events } = setup();
  run("tarn open docs/spec.md:12");
  assert.deepEqual(events.find(([n]) => n === "viewer.open")[1], { path: `${REPO}/docs/spec.md`, line: 12 });
  run("tarn open nope.md");
  assert.match(screen.text(), /tarn: no such file: nope\.md/);
  assert.equal(events.filter(([n]) => n === "viewer.open").length, 1);
});

test("only tarn new says it is planned, on its first run", () => {
  const { screen, run } = setup();
  run("tarn --help");
  assert.match(screen.text(), /usage: tarn .*new \(planned\)/);
  run("clear");
  run("tarn ls");
  assert.doesNotMatch(screen.text(), /planned:/);
  run("tarn new");
  assert.match(screen.text(), /planned: not in the app yet/);
  run("clear");
  run("tarn new");
  assert.doesNotMatch(screen.text(), /planned:/);
});

test("sleep runs on the clock and ctrl-C stops it", () => {
  const { screen, run, clock, shell, type } = setup();
  run("sleep 3");
  assert.equal(shell.busy, "sleep");
  clock.advance(2000);
  assert.equal(shell.busy, "sleep");
  clock.advance(1100);
  assert.equal(shell.busy, null);
  run("sleep 30");
  type("\x03");
  assert.equal(shell.busy, null);
  assert.match(screen.text(), /\^C/);
  clock.advance(60_000);
  assert.equal(shell.busy, null);
});

test("exit and ctrl-D close the pane", () => {
  const a = setup();
  a.run("exit");
  assert.ok(a.events.some(([n]) => n === "exit"));
  const b = setup();
  b.type("\x04");
  assert.ok(b.events.some(([n]) => n === "exit"));
});

test("claude runs a turn through a card answer", () => {
  const { screen, run, type, clock, events, vfs, shell } = setup();
  run("claude");
  assert.equal(shell.busy, "claude");
  type("update the spec\r");
  clock.advance(1);
  assert.deepEqual(hooks(events), ["UserPromptSubmit"]);
  clock.advance(3000);
  assert.deepEqual(hooks(events), ["UserPromptSubmit", "PostToolUse", "PermissionRequest"]);
  const request = events.find(([, d]) => d.name === "PermissionRequest")[1].event;
  assert.equal(request.answerable, true);
  const before = vfs.read(`${REPO}/docs/spec.md`);
  shell.answer(true);
  assert.equal(hooks(events).at(-1), "PostToolUse");
  assert.notEqual(vfs.read(`${REPO}/docs/spec.md`), before);
  clock.advance(4000);
  assert.equal(hooks(events).at(-1), "Stop");
  assert.match(screen.text(), /Done\. Request: update the spec/);
  type("/exit\r");
  assert.equal(hooks(events).at(-1), "SessionEnd");
  assert.equal(shell.busy, null);
});

test("claude: a terminal answer sends no event, the next tool does", () => {
  const { run, type, clock, events } = setup();
  run("claude");
  type("go\r");
  clock.advance(3000);
  type("y\r");
  assert.equal(hooks(events).at(-1), "PermissionRequest");
  clock.advance(1300);
  clock.advance(600);
  assert.equal(hooks(events).at(-1), "PostToolUse");
});

test("claude: a denied edit leaves the file and ends in Stop", () => {
  const { run, type, clock, events, vfs } = setup();
  const before = vfs.read(`${REPO}/docs/spec.md`);
  run("claude");
  type("go\r");
  clock.advance(3000);
  type("n\r");
  clock.advance(2000);
  assert.equal(hooks(events).at(-1), "Stop");
  assert.equal(vfs.read(`${REPO}/docs/spec.md`), before);
});

test("claude: ctrl-C aborts the turn and sends Stop, timers stop", () => {
  const { run, type, clock, events, screen } = setup();
  run("claude");
  type("go\r");
  clock.advance(1500);
  type("\x03");
  assert.equal(hooks(events).at(-1), "Stop");
  const count = hooks(events).length;
  clock.advance(10_000);
  assert.equal(hooks(events).length, count);
  assert.match(screen.text(), /Interrupted by user/);
});

test("claude --continue resumes without a banner", () => {
  const { screen, shell } = setup();
  shell.start({ resume: true });
  assert.doesNotMatch(screen.text(), /Claude Code/);
});

test("a name from Object.prototype is not a command", () => {
  const { screen, run } = setup();
  run("constructor");
  run("__proto__");
  assert.match(screen.text(), /zsh: command not found: constructor/);
  assert.match(screen.text(), /zsh: command not found: __proto__/);
});

test("rm -rf refuses the root and the home folder", () => {
  const { screen, run, vfs } = setup();
  run("rm -rf /");
  run("rm -rf ~");
  assert.match(screen.text(), /dangerous to operate recursively on '\/'/);
  assert.match(screen.text(), /dangerous to operate recursively on '\/Users\/you'/);
  assert.ok(vfs.exists(HOME) && vfs.exists(REPO));
});
