#!/usr/bin/env node
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const packageRoot = process.cwd();
const biomeScript = path.join(packageRoot, "node_modules", "@biomejs", "biome", "bin", "biome");

if (!fs.existsSync(biomeScript)) {
  process.exit(0);
}

if (isExecutableOnPath("biome")) {
  process.exit(0);
}

const pathEntries = (process.env.PATH ?? "")
  .split(path.delimiter)
  .filter(Boolean)
  .map((entry) => path.resolve(entry));

const homeDir = path.resolve(os.homedir());
const tmpDir = path.resolve(os.tmpdir());
const safeRoots = [homeDir, tmpDir, path.resolve("/usr/local"), path.resolve("/opt/homebrew")];
const candidates = new Set();

const bunPath = findExecutableOnPath("bun");
if (bunPath) {
  candidates.add(path.resolve(path.dirname(bunPath)));
}

if (process.env.BUN_INSTALL) {
  candidates.add(path.resolve(path.join(process.env.BUN_INSTALL, "bin")));
}

candidates.add(path.resolve(path.join(os.homedir(), ".bun", "bin")));
candidates.add(path.resolve(path.join(os.homedir(), ".local", "bin")));

for (const entry of pathEntries) {
  if (isSafePathEntry(entry, safeRoots)) {
    candidates.add(entry);
  }
}

for (const resolved of candidates) {
  if (!pathEntries.includes(resolved) || !isSafePathEntry(resolved, safeRoots)) {
    continue;
  }

  try {
    fs.mkdirSync(resolved, { recursive: true });
  } catch {
    continue;
  }

  const target = path.join(resolved, "biome");
  if (fs.existsSync(target)) {
    process.exit(0);
  }

  const escapedPath = biomeScript.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
  const script = `#!/usr/bin/env sh\nexec node "${escapedPath}" "$@"\n`;

  try {
    fs.writeFileSync(target, script, { mode: 0o755 });
    process.exit(0);
  } catch {
    // Ignore write failures to avoid breaking installs.
  }
}

process.exit(0);

function isExecutableOnPath(command) {
  return Boolean(findExecutableOnPath(command));
}

function isSafePathEntry(entry, safeRoots) {
  return safeRoots.some((root) => entry === root || entry.startsWith(`${root}${path.sep}`));
}

function findExecutableOnPath(command) {
  const searchPaths = (process.env.PATH ?? "").split(path.delimiter).filter(Boolean);
  for (const entry of searchPaths) {
    const candidate = path.join(entry, command);
    if (fs.existsSync(candidate)) {
      return candidate;
    }
  }
  return null;
}
