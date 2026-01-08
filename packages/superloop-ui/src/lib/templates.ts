const FRAME_WIDTH = 78;

export function buildPlaceholder(viewName: string, description?: string): string {
  const lines = [
    `SUPERLOOP UI: ${viewName}`,
    "",
    description ? `Description: ${description}` : "Description:",
    "",
    "Replace this text with your ASCII mockup.",
    "Use bindings like {{iteration}} or {{test_status}}.",
    "",
  ];

  return renderFrame(lines);
}

function renderFrame(lines: string[]): string {
  const top = `+${"-".repeat(FRAME_WIDTH)}+`;
  const body = lines.map((line) => {
    const padded = line.padEnd(FRAME_WIDTH, " ");
    return `|${padded}|`;
  });
  return [top, ...body, top].join("\n");
}
