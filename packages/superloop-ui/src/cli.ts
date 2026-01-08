import { Command } from "commander";

import { devCommand } from "./commands/dev.js";
import { exportPrototypeCommand } from "./commands/export.js";
import { generatePrototype } from "./commands/generate.js";
import { listPrototypesCommand } from "./commands/list.js";
import { refinePrototype } from "./commands/refine.js";
import { renderPrototypeCommand } from "./commands/render.js";
import { normalizeViewName } from "./lib/names.js";
import { resolveRepoRoot } from "./lib/paths.js";

const program = new Command();

program
  .name("superloop-ui")
  .description("Superloop UI prototyping framework")
  .option("--repo <path>", "Repo root (defaults to cwd)")
  .option("--loop <id>", "Loop id for data binding");

program
  .command("generate")
  .argument("<view>", "View name for the prototype")
  .option("-d, --description <text>", "Natural language description")
  .action(async (view, options) => {
    const repoRoot = resolveRepoRoot(program.opts().repo);
    const viewName = normalizeViewName(view);
    await generatePrototype({
      repoRoot,
      viewName,
      description: options.description
    });
  });

program
  .command("refine")
  .argument("<view>", "View name to refine")
  .option("-d, --description <text>", "Natural language description")
  .action(async (view, options) => {
    const repoRoot = resolveRepoRoot(program.opts().repo);
    const viewName = normalizeViewName(view);
    await refinePrototype({
      repoRoot,
      viewName,
      description: options.description
    });
  });

program
  .command("list")
  .description("List available prototypes")
  .action(async () => {
    const repoRoot = resolveRepoRoot(program.opts().repo);
    await listPrototypesCommand({ repoRoot });
  });

program
  .command("render")
  .argument("<view>", "View name to render")
  .option("-v, --version <id>", "Version id or filename")
  .option("-r, --renderer <mode>", "Renderer: cli or tui", "cli")
  .option("--raw", "Skip data binding")
  .action(async (view, options) => {
    const repoRoot = resolveRepoRoot(program.opts().repo);
    const viewName = normalizeViewName(view);
    const renderer = options.renderer === "tui" ? "tui" : "cli";
    await renderPrototypeCommand({
      repoRoot,
      viewName,
      versionId: options.version,
      renderer,
      loopId: program.opts().loop,
      raw: Boolean(options.raw)
    });
  });

program
  .command("export")
  .argument("<view>", "View name to export")
  .option("-v, --version <id>", "Version id or filename")
  .option("-o, --out <dir>", "Output directory", "./superloop-ui-export")
  .action(async (view, options) => {
    const repoRoot = resolveRepoRoot(program.opts().repo);
    const viewName = normalizeViewName(view);
    await exportPrototypeCommand({
      repoRoot,
      viewName,
      versionId: options.version,
      loopId: program.opts().loop,
      outDir: options.out
    });
  });

program
  .command("dev")
  .description("Start the WorkGrid dev server")
  .option("-p, --port <port>", "Port", "5173")
  .option("--host <host>", "Host", "localhost")
  .option("--no-open", "Disable auto-open in browser")
  .action(async (options) => {
    const repoRoot = resolveRepoRoot(program.opts().repo);
    const port = Number(options.port);
    await devCommand({
      repoRoot,
      loopId: program.opts().loop,
      port: Number.isNaN(port) ? 5173 : port,
      host: options.host,
      open: options.open
    });
  });

program.parse();
