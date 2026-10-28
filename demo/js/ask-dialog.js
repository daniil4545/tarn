// A small modal question with named buttons; resolves with the label of the button pressed
// (the last one on Escape, the first on Enter). The app asks Save / Don't Save / Cancel the same
// way. `body` (form controls) goes between the text and the buttons; the caller reads it.
export function ask(message, labels, body = null) {
  return new Promise((resolve) => {
    const box = document.createElement("div");
    box.className = "ask-dialog";
    box.setAttribute("role", "dialog");
    box.setAttribute("aria-modal", "true");
    const text = Object.assign(document.createElement("p"), { textContent: message });
    box.append(text, ...(body ? [body] : []), ...labels.map((label) => Object.assign(document.createElement("button"), { textContent: label })));
    const done = (label) => {
      box.remove();
      document.removeEventListener("keydown", onKey, true);
      resolve(label);
    };
    const onKey = (e) => {
      if (e.key === "Enter" && body && e.target.tagName === "INPUT") {
        e.preventDefault();
        e.stopPropagation();
        return done(labels[0]);
      }
      if (e.key !== "Escape") return;
      e.stopPropagation();
      done(labels.at(-1));
    };
    box.addEventListener("click", (e) => { if (e.target.tagName === "BUTTON") done(e.target.textContent); });
    document.addEventListener("keydown", onKey, true);
    document.getElementById("window").append(box);
    (box.querySelector("input:not([type=radio]):not([type=checkbox])") ?? box.querySelector("button")).focus();
  });
}
