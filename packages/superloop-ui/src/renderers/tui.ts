import * as blessed from "blessed";

import { buildFrame, frameToText } from "./frame.js";

export async function renderTui(text: string, title?: string): Promise<void> {
  const framed = frameToText(buildFrame(text, title));
  return new Promise((resolve) => {
    const screen = blessed.screen({
      smartCSR: true,
      title: title ?? "Superloop UI",
    });

    const box = blessed.box({
      top: "center",
      left: "center",
      width: "90%",
      height: "90%",
      content: framed,
      tags: false,
      scrollable: true,
      alwaysScroll: true,
      keys: true,
      vi: true,
    });

    screen.append(box);
    screen.key(["q", "C-c", "escape"], () => {
      screen.destroy();
      resolve();
    });

    screen.render();
  });
}
