import chalk from "chalk";

import { buildFrame } from "./frame.js";

export function renderCli(text: string, title?: string): string {
  const frame = buildFrame(text, title);
  const styledBorder = chalk.cyan(frame.border);

  const body = frame.bodyLines.map((line) => {
    return chalk.cyan("| ") + chalk.white(line) + chalk.cyan(" |");
  });

  if (frame.titleLine) {
    const titleLine = chalk.cyan("|") + chalk.cyan(frame.titleLine) + chalk.cyan("|");
    return [styledBorder, titleLine, styledBorder, ...body, styledBorder].join("\n");
  }

  return [styledBorder, ...body, styledBorder].join("\n");
}
