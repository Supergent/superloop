import fs from "node:fs/promises";

export async function fileExists(path: string): Promise<boolean> {
  try {
    await fs.access(path);
    return true;
  } catch {
    return false;
  }
}

export async function readJson<T>(path: string): Promise<T | null> {
  try {
    const raw = await fs.readFile(path, "utf8");
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
}
