import path from "node:path";

export const SUPERLOOP_DIR = ".superloop";
export const UI_PROTOTYPES_DIR = path.join(SUPERLOOP_DIR, "ui", "prototypes");
export const LOOPS_DIR = path.join(SUPERLOOP_DIR, "loops");

export function resolveRepoRoot(repoRoot?: string): string {
  return repoRoot ? path.resolve(repoRoot) : process.cwd();
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
