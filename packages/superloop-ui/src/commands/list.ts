import chalk from "chalk";

import { listPrototypes } from "../lib/prototypes.js";

export async function listPrototypesCommand(params: { repoRoot: string }): Promise<void> {
  const views = await listPrototypes(params.repoRoot);
  if (views.length === 0) {
    console.log(chalk.yellow("No prototypes found."));
    return;
  }

  for (const view of views) {
    console.log(chalk.cyan(view.name));
    if (view.description) {
      console.log(`  ${chalk.dim(view.description)}`);
    }
    for (const version of view.versions) {
      console.log(`  - ${version.filename} (${version.createdAt})`);
    }
  }
}
