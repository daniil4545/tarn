// A small modal question with named buttons; resolves with the label of the button pressed
// (the last one on Escape). The app asks Save / Don't Save / Cancel the same way.
export function ask(message, labels) {
  return new Promise((resolve) => {
    const box = document.createElement("div");
    box.className = "ask-dialog";
    box.setAttribute("role", "dialog");
    box.setAttribute("aria-modal", "true");
    const text = Object.assign(document.createElement("p"), { textContent: message });
    box.append(text, ...labels.map((label) => Object.assign(document.createElement("button"), { textContent: label })));
    const done = (label) => {
      box.remove();
      document.removeEventListener("keydown", onKey, true);
      resolve(label);
    };
    const onKey = (e) => {
      if (e.key !== "Escape") return;
      e.stopPropagation();
      done(labels.at(-1));
    };
    box.addEventListener("click", (e) => { if (e.target.tagName === "BUTTON") done(e.target.textContent); });
    document.addEventListener("keydown", onKey, true);
    document.getElementById("window").append(box);
    box.querySelector("button").focus();
  });
}
