import { input } from "@inquirer/prompts";
import ora from "ora";

import { createPrototypeVersion } from "../lib/prototypes.js";
import { buildPlaceholder } from "../lib/templates.js";

export async function generatePrototype(params: {
  repoRoot: string;
  viewName: string;
  description?: string;
}): Promise<void> {
  const description = params.description?.trim()
    ? params.description.trim()
    : await input({ message: "Describe the view you want to prototype" });

  const spinner = ora("Creating prototype...").start();
  const content = buildPlaceholder(params.viewName, description);
  const version = await createPrototypeVersion({
    repoRoot: params.repoRoot,
    viewName: params.viewName,
    content,
    description,
    prompt: description
  });
  spinner.succeed(`Prototype created at ${version.path}`);
}
