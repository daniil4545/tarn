import { startAgentSession } from "../agent-script.js";

// `claude --continue` re-enters a running session without the banner (seeded agent panes).
export function claude(ctx) {
  startAgentSession(ctx, { banner: !ctx.args.includes("--continue") });
}
