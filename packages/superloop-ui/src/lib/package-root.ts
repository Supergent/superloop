import path from "node:path";
import { fileURLToPath } from "node:url";

export function resolvePackageRoot(metaUrl: string): string {
  const filename = fileURLToPath(metaUrl);
  const dir = path.dirname(filename);
  return path.resolve(dir, "..");
}
