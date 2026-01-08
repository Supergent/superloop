import chalk from "chalk";

import { injectBindings } from "../lib/bindings.js";
import { type PrototypeVersion, readLatestPrototype } from "../lib/prototypes.js";
import { loadSuperloopData } from "../lib/superloop-data.js";
import { renderCli } from "../renderers/cli.js";
import { renderTui } from "../renderers/tui.js";

export async function renderPrototypeCommand(params: {
  repoRoot: string;
  viewName: string;
  versionId?: string;
  renderer: "cli" | "tui";
  loopId?: string;
  raw?: boolean;
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

  let content = version.content;
  if (!params.raw) {
    const superloop = await loadSuperloopData({
      repoRoot: params.repoRoot,
      loopId: params.loopId,
    });
    content = injectBindings(content, superloop.data);
  }

  if (params.renderer === "tui") {
    await renderTui(content, view.name);
    return;
  }

  console.log(renderCli(content, view.name));
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
