import { input } from "@inquirer/prompts";
import ora from "ora";

import { createPrototypeVersion, readLatestPrototype } from "../lib/prototypes.js";

export async function refinePrototype(params: {
  repoRoot: string;
  viewName: string;
  description?: string;
}): Promise<void> {
  const spinner = ora("Creating refinement...").start();
  const view = await readLatestPrototype({
    repoRoot: params.repoRoot,
    viewName: params.viewName,
  });

  if (!view) {
    spinner.fail(`No existing prototype found for ${params.viewName}`);
    return;
  }

  const description = params.description?.trim()
    ? params.description.trim()
    : await input({ message: "Describe the refinement you want to apply" });

  const version = await createPrototypeVersion({
    repoRoot: params.repoRoot,
    viewName: params.viewName,
    content: view.latest.content,
    description,
  });

  spinner.succeed(`Refinement created at ${version.path}`);
}
