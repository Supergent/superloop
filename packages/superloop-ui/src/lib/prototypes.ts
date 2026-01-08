import fs from "node:fs/promises";
import path from "node:path";

import { fileExists, readJson } from "./fs-utils.js";
import { resolvePrototypesRoot } from "./paths.js";

export type PrototypeVersion = {
  id: string;
  filename: string;
  path: string;
  createdAt: string;
  content: string;
};

export type PrototypeView = {
  name: string;
  description?: string;
  versions: PrototypeVersion[];
  latest: PrototypeVersion;
};

type PrototypeMeta = {
  description?: string;
  prompt?: string;
  createdAt?: string;
  updatedAt?: string;
};

const VERSION_EXTENSION = ".txt";
const META_FILENAME = "meta.json";
const TIMESTAMP_PATTERN = /^(\d{8}-\d{6})/;

export function createTimestampId(date = new Date()): string {
  const pad = (value: number) => value.toString().padStart(2, "0");
  const year = date.getFullYear();
  const month = pad(date.getMonth() + 1);
  const day = pad(date.getDate());
  const hours = pad(date.getHours());
  const minutes = pad(date.getMinutes());
  const seconds = pad(date.getSeconds());
  return `${year}${month}${day}-${hours}${minutes}${seconds}`;
}

export function formatTimestamp(date: Date): string {
  const pad = (value: number) => value.toString().padStart(2, "0");
  const year = date.getFullYear();
  const month = pad(date.getMonth() + 1);
  const day = pad(date.getDate());
  const hours = pad(date.getHours());
  const minutes = pad(date.getMinutes());
  const seconds = pad(date.getSeconds());
  return `${year}-${month}-${day} ${hours}:${minutes}:${seconds}`;
}

export async function listPrototypes(repoRoot: string): Promise<PrototypeView[]> {
  const root = resolvePrototypesRoot(repoRoot);
  if (!(await fileExists(root))) {
    return [];
  }

  const entries = await fs.readdir(root, { withFileTypes: true });
  const views: PrototypeView[] = [];

  for (const entry of entries) {
    if (entry.isDirectory()) {
      const view = await readViewDirectory(root, entry.name);
      if (view) {
        views.push(view);
      }
      continue;
    }

    if (entry.isFile() && entry.name.endsWith(VERSION_EXTENSION)) {
      const view = await readStandalonePrototype(root, entry.name);
      if (view) {
        views.push(view);
      }
    }
  }

  return views.sort((a, b) => a.name.localeCompare(b.name));
}

export async function createPrototypeVersion(params: {
  repoRoot: string;
  viewName: string;
  content: string;
  description?: string;
  prompt?: string;
}): Promise<PrototypeVersion> {
  const root = resolvePrototypesRoot(params.repoRoot);
  const viewDir = path.join(root, params.viewName);
  await fs.mkdir(viewDir, { recursive: true });

  const timestampId = createTimestampId();
  const filename = `${timestampId}${VERSION_EXTENSION}`;
  const filePath = path.join(viewDir, filename);
  await fs.writeFile(filePath, params.content, "utf8");

  const metaPath = path.join(viewDir, META_FILENAME);
  const meta = (await readJson<PrototypeMeta>(metaPath)) ?? {};
  const now = new Date().toISOString();
  const nextMeta: PrototypeMeta = {
    description: params.description ?? meta.description,
    prompt: params.prompt ?? meta.prompt,
    createdAt: meta.createdAt ?? now,
    updatedAt: now
  };
  await fs.writeFile(metaPath, JSON.stringify(nextMeta, null, 2), "utf8");

  return {
    id: timestampId,
    filename,
    path: filePath,
    createdAt: formatTimestamp(new Date()),
    content: params.content
  };
}

export async function readLatestPrototype(params: {
  repoRoot: string;
  viewName: string;
}): Promise<PrototypeView | null> {
  const root = resolvePrototypesRoot(params.repoRoot);
  const viewDir = path.join(root, params.viewName);
  if (!(await fileExists(viewDir))) {
    return null;
  }
  const view = await readViewDirectory(root, params.viewName);
  return view ?? null;
}

async function readStandalonePrototype(root: string, filename: string): Promise<PrototypeView | null> {
  const viewName = path.basename(filename, VERSION_EXTENSION);
  const filePath = path.join(root, filename);
  const stats = await fs.stat(filePath);
  const content = await fs.readFile(filePath, "utf8");
  const createdAt = formatTimestamp(stats.mtime);
  const version: PrototypeVersion = {
    id: createTimestampId(stats.mtime),
    filename,
    path: filePath,
    createdAt,
    content
  };

  return {
    name: viewName,
    versions: [version],
    latest: version
  };
}

async function readViewDirectory(root: string, viewName: string): Promise<PrototypeView | null> {
  const viewDir = path.join(root, viewName);
  const entries = await fs.readdir(viewDir, { withFileTypes: true });
  const versions: PrototypeVersion[] = [];
  let description: string | undefined;

  for (const entry of entries) {
    if (entry.isFile() && entry.name === META_FILENAME) {
      const meta = await readJson<PrototypeMeta>(path.join(viewDir, entry.name));
      description = meta?.description;
      continue;
    }

    if (entry.isFile() && entry.name.endsWith(VERSION_EXTENSION)) {
      const filePath = path.join(viewDir, entry.name);
      const stats = await fs.stat(filePath);
      const content = await fs.readFile(filePath, "utf8");
      const createdAt = formatTimestamp(stats.mtime);
      const versionId = readVersionId(entry.name, stats.mtime);
      versions.push({
        id: versionId,
        filename: entry.name,
        path: filePath,
        createdAt,
        content
      });
    }
  }

  if (versions.length === 0) {
    return null;
  }

  versions.sort((a, b) => a.createdAt.localeCompare(b.createdAt));
  const latest = versions[versions.length - 1];

  return {
    name: viewName,
    description,
    versions,
    latest
  };
}

function readVersionId(filename: string, fallbackDate: Date): string {
  const match = filename.match(TIMESTAMP_PATTERN);
  if (match?.[1]) {
    return match[1];
  }
  return createTimestampId(fallbackDate);
}
