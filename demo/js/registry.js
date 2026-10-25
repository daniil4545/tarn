// The only writer of agent state. Counterpart of SessionRegistry.swift and AgentSession.handle.
// Input: `hook` commands carrying the hook events of docs/spec.md section 8.
import { bus } from "./bus.js";
import { register, read } from "./state.js";
import { SESSIONS } from "./seed.js";

export function newSession(now) {
  return { state: "idle", since: now, seen: true, failed: false, request: null, sawPermissionRequest: false, permissionAgent: null, answerable: false };
}

// Pure transition table. Returns the next session; the caller stamps `since` and `seen`.
export function handle(session, name, event = {}) {
  const next = { ...session };
  const agent = event.agent_id ?? null;
  const sub = agent !== null;
  const settle = () => { next.request = null; next.answerable = false; };

  switch (name) {
    case "UserPromptSubmit":
      if (sub) break;
      Object.assign(next, { state: "working", failed: false, sawPermissionRequest: false, permissionAgent: null });
      settle();
      break;
    case "PermissionRequest":
      Object.assign(next, { state: "permission", request: event.request ?? null, sawPermissionRequest: true, permissionAgent: agent, answerable: event.answerable === true });
      break;
    case "PostToolUse":
    case "PostToolUseFailure": {
      const own = session.state === "permission" && agent === session.permissionAgent;
      const idleMain = !sub && session.state !== "working" && session.state !== "permission";
      if (own || idleMain) { next.state = "working"; settle(); }
      break;
    }
    case "Notification":
      if (sub) break;
      if (event.notification_type === "permission_prompt" && session.state === "working" && !session.sawPermissionRequest) {
        Object.assign(next, { state: "permission", permissionAgent: null });
      } else if (event.notification_type === "idle_prompt" && session.state === "idle") {
        next.state = "waiting";
      }
      break;
    case "Stop":
      if (sub) break;
      if (event.background_tasks?.length) next.state = "working";
      else { next.state = "waiting"; settle(); }
      break;
    case "StopFailure":
      if (sub) break;
      Object.assign(next, { state: "waiting", failed: true });
      settle();
      break;
    case "SessionEnd":
      if (sub) break;
      next.state = event.reason === "clear" ? "waiting" : "idle";
      settle();
      break;
  }
  return next;
}

export function startRegistry({ now, isFocused }) {
  const seed = Object.fromEntries(Object.entries(SESSIONS).map(([pane, s]) => [pane, { ...newSession(now()), ...s }]));
  const write = register("registry", seed);

  bus.handle("hook", ({ pane, name, event }) => {
    const sessions = read("registry");
    const old = sessions[pane] ?? newSession(now());
    const next = handle(old, name, event);
    if (next.state !== old.state) Object.assign(next, { since: now(), seen: isFocused(pane) });
    write({ ...sessions, [pane]: next });
  });

  // Focusing a pane marks its session seen; disposing a pane (after the undo window) drops the record.
  bus.on("pane:focused", ({ pane }) => {
    const s = read("registry")[pane];
    if (s && !s.seen) write({ ...read("registry"), [pane]: { ...s, seen: true } });
  });
  bus.on("pane:disposed", ({ pane }) => {
    write(Object.fromEntries(Object.entries(read("registry")).filter(([id]) => id !== pane)));
  });
}
