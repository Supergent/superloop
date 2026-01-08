import chalk from "chalk";

export function renderCli(text: string, title?: string): string {
  const lines = text.split("\n");
  const contentWidth = Math.max(
    ...lines.map((line) => line.length),
    title ? title.length + 2 : 0
  );
  const border = `+${"-".repeat(contentWidth + 2)}+`;
  const styledBorder = chalk.cyan(border);

  const body = lines.map((line) => {
    const padded = line.padEnd(contentWidth, " ");
    return chalk.cyan(`| `) + chalk.white(padded) + chalk.cyan(" |");
  });

  if (title) {
    const titleText = ` ${title} `;
    const paddedTitle = titleText.padEnd(contentWidth + 2, " ");
    const titleLine = chalk.cyan("|") + chalk.cyan(paddedTitle) + chalk.cyan("|");
    return [styledBorder, titleLine, styledBorder, ...body, styledBorder].join("\n");
  }

  return [styledBorder, ...body, styledBorder].join("\n");
}
