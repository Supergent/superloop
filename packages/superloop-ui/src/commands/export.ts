import fs from "node:fs/promises";
import path from "node:path";
import chalk from "chalk";

import { injectBindings } from "../lib/bindings.js";
import { type PrototypeVersion, readLatestPrototype } from "../lib/prototypes.js";
import { loadSuperloopData } from "../lib/superloop-data.js";

export async function exportPrototypeCommand(params: {
  repoRoot: string;
  viewName: string;
  versionId?: string;
  outDir: string;
  loopId?: string;
}): Promise<void> {
  const view = await readLatestPrototype({
    repoRoot: params.repoRoot,
    viewName: params.viewName,
  });

  if (!view) {
    console.log(chalk.red(`Prototype ${params.viewName} not found.`));
    return;
  }

  const version = selectVersion(view.versions, params.versionId);
  if (!version) {
    console.log(chalk.red(`Version ${params.versionId} not found.`));
    return;
  }

  const superloop = await loadSuperloopData({
    repoRoot: params.repoRoot,
    loopId: params.loopId,
  });
  const rendered = injectBindings(version.content, superloop.data);

  const outDir = path.resolve(params.outDir);
  await fs.mkdir(outDir, { recursive: true });

  const html = buildHtml(view.name, rendered);
  const css = buildCss();

  await fs.writeFile(path.join(outDir, "index.html"), html, "utf8");
  await fs.writeFile(path.join(outDir, "styles.css"), css, "utf8");
  await fs.writeFile(path.join(outDir, "mockup.txt"), rendered, "utf8");

  console.log(chalk.green(`Exported scaffold to ${outDir}`));
}

function selectVersion(versions: PrototypeVersion[], versionId?: string) {
  if (!versionId) {
    return versions[versions.length - 1];
  }
  return (
    versions.find((version) => version.id === versionId) ??
    versions.find((version) => version.filename === versionId)
  );
}

function buildHtml(title: string, content: string): string {
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>${escapeHtml(title)} - Superloop UI</title>
    <link rel="stylesheet" href="styles.css" />
  </head>
  <body>
    <main class="stage">
      <h1>${escapeHtml(title)}</h1>
      <pre class="mockup">${escapeHtml(content)}</pre>
    </main>
  </body>
</html>
`;
}

function buildCss(): string {
  return `:root {
  color-scheme: light;
  --bg: #0f172a;
  --panel: #0b1220;
  --text: #e2e8f0;
  --accent: #38bdf8;
}

* {
  box-sizing: border-box;
}

body {
  margin: 0;
  min-height: 100vh;
  font-family: "Space Mono", "Fira Code", "Menlo", monospace;
  background: radial-gradient(circle at top, #10213f 0%, #070b14 55%, #030507 100%);
  color: var(--text);
}

.stage {
  max-width: 960px;
  margin: 0 auto;
  padding: 64px 24px;
}

h1 {
  margin: 0 0 24px;
  font-size: 28px;
  letter-spacing: 0.04em;
}

.mockup {
  padding: 24px;
  background: var(--panel);
  border: 1px solid rgba(56, 189, 248, 0.4);
  border-radius: 16px;
  white-space: pre-wrap;
  box-shadow: 0 20px 50px rgba(0, 0, 0, 0.4);
}
`;
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/\"/g, "&quot;")
    .replace(/'/g, "&#039;");
}
