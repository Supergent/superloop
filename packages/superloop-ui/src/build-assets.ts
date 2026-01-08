import fs from "node:fs/promises";
import path from "node:path";

import { resolvePackageRoot } from "./lib/package-root.js";

async function copyAssets() {
  const packageRoot = resolvePackageRoot(import.meta.url);
  const srcRoot = path.join(packageRoot, "src", "web");
  const distRoot = path.join(packageRoot, "dist", "web");

  await fs.mkdir(distRoot, { recursive: true });
  await fs.copyFile(path.join(srcRoot, "index.html"), path.join(distRoot, "index.html"));
}

copyAssets().catch((error) => {
  console.error(error);
  process.exit(1);
});
