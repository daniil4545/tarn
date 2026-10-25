// clipboard-paste-protection: a multi-line paste waits for a confirmation, as in Ghostty.

function confirmPaste(el, text, lines, paste) {
  const dialog = document.createElement("div");
  dialog.className = "paste-dialog";
  dialog.setAttribute("role", "dialog");
  dialog.innerHTML = `<p>Paste ${lines} lines? A pasted line break can run a command.</p>
    <button data-paste>Paste</button><button data-cancel>Cancel</button>`;
  const close = (ok) => {
    dialog.remove();
    if (ok) paste(text);
  };
  dialog.querySelector("[data-paste]").addEventListener("click", () => close(true));
  dialog.querySelector("[data-cancel]").addEventListener("click", () => close(false));
  el.append(dialog);
  dialog.querySelector("[data-paste]").focus();
}

// `enabled()` is read at paste time; `paste(text)` sends the text to the terminal.
export function guardPaste(el, { enabled, paste }) {
  el.addEventListener("paste", (e) => {
    const text = e.clipboardData?.getData("text") ?? "";
    const lines = text.replace(/\r?\n$/, "").split(/\r?\n/).length;
    if (!enabled() || lines < 2) return;
    e.preventDefault();
    e.stopPropagation();
    confirmPaste(el, text, lines, paste);
  }, true);
}
