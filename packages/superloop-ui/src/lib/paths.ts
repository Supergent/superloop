import fs from "node:fs";
import path from "node:path";

export const SUPERLOOP_DIR = ".superloop";
export const UI_PROTOTYPES_DIR = path.join(SUPERLOOP_DIR, "ui", "prototypes");
export const LOOPS_DIR = path.join(SUPERLOOP_DIR, "loops");

export function resolveRepoRoot(repoRoot?: string): string {
  if (repoRoot) {
    return path.resolve(repoRoot);
  }

  // Walk up to locate the Superloop repo root so CLI commands work from subdirs.
  const cwd = process.cwd();
  let current = cwd;
  let gitRoot: string | null = null;

  while (true) {
    if (fs.existsSync(path.join(current, SUPERLOOP_DIR))) {
      return current;
    }

    if (fs.existsSync(path.join(current, "superloop.sh"))) {
      return current;
    }

    if (!gitRoot && fs.existsSync(path.join(current, ".git"))) {
      gitRoot = current;
    }

    const parent = path.dirname(current);
    if (parent === current) {
      break;
    }
    current = parent;
  }

  return gitRoot ?? cwd;
}

export function resolvePrototypesRoot(repoRoot: string): string {
  return path.join(repoRoot, UI_PROTOTYPES_DIR);
}

export function resolveLoopsRoot(repoRoot: string): string {
  return path.join(repoRoot, LOOPS_DIR);
}

export function resolveLoopDir(repoRoot: string, loopId: string): string {
  return path.join(resolveLoopsRoot(repoRoot), loopId);
}
