#!/usr/bin/env node
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const packageRoot = process.cwd();
const biomeScript = path.join(
  packageRoot,
  "node_modules",
  "@biomejs",
  "biome",
  "bin",
  "biome"
);

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

const candidates = [];

if (process.env.BUN_INSTALL) {
  candidates.push(path.join(process.env.BUN_INSTALL, "bin"));
}

candidates.push(path.join(os.homedir(), ".bun", "bin"));
candidates.push(path.join(os.homedir(), ".local", "bin"));

for (const dir of candidates) {
  const resolved = path.resolve(dir);
  if (!pathEntries.includes(resolved)) {
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
  const searchPaths = (process.env.PATH ?? "").split(path.delimiter).filter(Boolean);
  for (const entry of searchPaths) {
    const candidate = path.join(entry, command);
    if (fs.existsSync(candidate)) {
      return true;
    }
  }
  return false;
}
