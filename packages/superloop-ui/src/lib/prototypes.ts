/**
 * @deprecated ASCII Prototype System (Legacy)
 *
 * This module is deprecated in favor of the Liquid Interface versioning system.
 * Use `@superloop-ui/liquid/storage` instead for versioned UI views.
 *
 * The ASCII prototype system stored text-based mockups. The new liquid system
 * stores typed UITree JSON with full component validation and version history.
 *
 * Migration path:
 * - Use `saveVersion()` from `./liquid/storage.js` to save UITrees
 * - Use `loadView()` to load versioned views
 * - Use the Dashboard's version selector for history navigation
 *
 * This file is kept for backwards compatibility but will be removed in a future version.
 */

import fs from "node:fs/promises";
import path from "node:path";

import { fileExists, readJson } from "./fs-utils.js";
import { resolvePrototypesRoot } from "./paths.js";

/** @deprecated Use ViewVersion from ./liquid/storage.js */
export type PrototypeVersion = {
  id: string;
  filename: string;
  path: string;
  createdAt: string;
  content: string;
};

/** @deprecated Use LiquidView from ./liquid/storage.js */
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
  const viewsByName = new Map<string, PrototypeView>();

  for (const entry of entries) {
    if (entry.isDirectory()) {
      const view = await readViewDirectory(root, entry.name);
      if (view) {
        viewsByName.set(view.name, view);
      }
    }
  }

  for (const entry of entries) {
    if (!entry.isFile() || !entry.name.endsWith(VERSION_EXTENSION)) {
      continue;
    }

    const viewName = path.basename(entry.name, VERSION_EXTENSION);
    const filePath = path.join(root, entry.name);
    const version = await readVersionFile(filePath, entry.name);
    const existing = viewsByName.get(viewName);

    if (existing) {
      if (!existing.versions.some((item) => item.filename === entry.name)) {
        existing.versions.push(version);
      }
      existing.versions.sort((a, b) => a.createdAt.localeCompare(b.createdAt));
      existing.latest = existing.versions[existing.versions.length - 1];
    } else {
      viewsByName.set(viewName, {
        name: viewName,
        versions: [version],
        latest: version,
      });
    }
  }

  return Array.from(viewsByName.values()).sort((a, b) => a.name.localeCompare(b.name));
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
    updatedAt: now,
  };
  await fs.writeFile(metaPath, JSON.stringify(nextMeta, null, 2), "utf8");

  return {
    id: timestampId,
    filename,
    path: filePath,
    createdAt: formatTimestamp(new Date()),
    content: params.content,
  };
}

export async function readLatestPrototype(params: {
  repoRoot: string;
  viewName: string;
}): Promise<PrototypeView | null> {
  const root = resolvePrototypesRoot(params.repoRoot);
  const viewDir = path.join(root, params.viewName);
  const view = (await fileExists(viewDir)) ? await readViewDirectory(root, params.viewName) : null;

  const standaloneName = `${params.viewName}${VERSION_EXTENSION}`;
  const standalonePath = path.join(root, standaloneName);
  if (await fileExists(standalonePath)) {
    const version = await readVersionFile(standalonePath, standaloneName);
    if (view) {
      if (!view.versions.some((item) => item.filename === standaloneName)) {
        view.versions.push(version);
      }
      view.versions.sort((a, b) => a.createdAt.localeCompare(b.createdAt));
      view.latest = view.versions[view.versions.length - 1];
      return view;
    }

    return {
      name: params.viewName,
      versions: [version],
      latest: version,
    };
  }

  return view ?? null;
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
      const version = await readVersionFile(filePath, entry.name);
      versions.push(version);
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
    latest,
  };
}

function readVersionId(filename: string, fallbackDate: Date): string {
  const match = filename.match(TIMESTAMP_PATTERN);
  if (match?.[1]) {
    return match[1];
  }
  return createTimestampId(fallbackDate);
}

async function readVersionFile(filePath: string, filename: string): Promise<PrototypeVersion> {
  const stats = await fs.stat(filePath);
  const content = await fs.readFile(filePath, "utf8");
  const versionId = readVersionId(filename, stats.mtime);
  const createdAt = formatTimestamp(resolveTimestamp(versionId, stats.mtime));

  return {
    id: versionId,
    filename,
    path: filePath,
    createdAt,
    content,
  };
}

function resolveTimestamp(versionId: string, fallbackDate: Date): Date {
  const parsed = parseTimestampId(versionId);
  return parsed ?? fallbackDate;
}

function parseTimestampId(versionId: string): Date | null {
  const match = versionId.match(TIMESTAMP_PATTERN);
  if (!match?.[1]) {
    return null;
  }

  const id = match[1];
  const year = Number(id.slice(0, 4));
  const month = Number(id.slice(4, 6));
  const day = Number(id.slice(6, 8));
  const hours = Number(id.slice(9, 11));
  const minutes = Number(id.slice(11, 13));
  const seconds = Number(id.slice(13, 15));
  const date = new Date(year, month - 1, day, hours, minutes, seconds);

  if (Number.isNaN(date.getTime())) {
    return null;
  }

  return date;
}
