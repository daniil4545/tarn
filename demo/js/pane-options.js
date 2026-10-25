// Maps config values (Ghostty spelling, js/config.js) to terminal engine settings.
import { themeFor } from "./themes.js";

const DEFAULT_FONT = "JetBrains Mono";

// A font name as a CSS string: a quote or backslash in the name must not end the string early.
const cssString = (name) => `"${name.replace(/[\\"]/g, "\\$&")}"`;

// Config key -> engine option it drives.
export const ENGINE_KEYS = {
  theme: "theme",
  "font-family": "fontFamily",
  "font-size": "fontSize",
  "cursor-style": "cursorStyle",
  "cursor-style-blink": "cursorBlink",
};

export const effectiveSize = (config, adjust) => Math.min(48, Math.max(6, config["font-size"] + adjust));

export function engineOptions(config, adjust) {
  return {
    theme: themeFor(config.theme),
    fontFamily: `${cssString(config["font-family"] || DEFAULT_FONT)}, ${cssString(DEFAULT_FONT)}, monospace`,
    fontSize: effectiveSize(config, adjust),
    cursorStyle: config["cursor-style"],
    cursorBlink: config["cursor-style-blink"] !== "false",
  };
}

// The adapter knows one Option-as-Alt switch; left and right both turn it on.
export const optionAsAlt = (value) => ["true", "left", "right"].includes(value);
export const copyOnSelect = (value) => value === "clipboard";
