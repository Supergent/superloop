export type FrameData = {
  contentWidth: number;
  border: string;
  titleLine?: string;
  bodyLines: string[];
};

export function buildFrame(text: string, title?: string): FrameData {
  const lines = text.split("\n");
  const titleWidth = title ? title.length + 2 : 0;
  const contentWidth = Math.max(...lines.map((line) => line.length), titleWidth);
  const border = `+${"-".repeat(contentWidth + 2)}+`;
  const bodyLines = lines.map((line) => line.padEnd(contentWidth, " "));
  const titleLine = title ? ` ${title} `.padEnd(contentWidth + 2, " ") : undefined;

  return {
    contentWidth,
    border,
    titleLine,
    bodyLines,
  };
}

export function frameToText(frame: FrameData): string {
  const lines = [frame.border];

  if (frame.titleLine) {
    lines.push(`|${frame.titleLine}|`, frame.border);
  }

  for (const line of frame.bodyLines) {
    lines.push(`| ${line} |`);
  }

  lines.push(frame.border);
  return lines.join("\n");
}
