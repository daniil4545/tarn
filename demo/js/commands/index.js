import { FS_COMMANDS } from "./fs.js";
import { BASIC_COMMANDS } from "./basic.js";
import { git } from "./git.js";
import { tarn } from "./tarn.js";
import { claude } from "./claude.js";

export const COMMANDS = { ...FS_COMMANDS, ...BASIC_COMMANDS, git, tarn, claude };
export const COMMAND_NAMES = Object.keys(COMMANDS).sort();
