// Prompt text: user@host cwd (branch) %, and the remote form user@host:cwd #.
import { blue, green, magenta, yellow } from "./ansi.js";

export function tilde(path, home) {
  if (path === home) return "~";
  return path.startsWith(`${home}/`) ? `~${path.slice(home.length)}` : path;
}

export function buildPrompt({ identity, cwd, branch }) {
  const where = tilde(cwd, identity.home);
  if (identity.remote) return `${identity.user}@${identity.host}:${where}# `;
  const git = branch ? ` ${yellow(`(${branch})`)}` : "";
  return `${blue(identity.user)}@${magenta(identity.host)} ${green(where)}${git} % `;
}
