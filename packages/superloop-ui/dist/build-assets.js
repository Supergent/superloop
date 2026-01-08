// src/build-assets.ts
import fs from "fs/promises";
import path2 from "path";

// src/lib/package-root.ts
import path from "path";
import { fileURLToPath } from "url";
function resolvePackageRoot(metaUrl) {
  const filename = fileURLToPath(metaUrl);
  const dir = path.dirname(filename);
  return path.resolve(dir, "..");
}

// src/build-assets.ts
async function copyAssets() {
  const packageRoot = resolvePackageRoot(import.meta.url);
  const srcRoot = path2.join(packageRoot, "src", "web");
  const distRoot = path2.join(packageRoot, "dist", "web");
  await fs.mkdir(distRoot, { recursive: true });
  await fs.copyFile(path2.join(srcRoot, "index.html"), path2.join(distRoot, "index.html"));
}
copyAssets().catch((error) => {
  console.error(error);
  process.exit(1);
});
