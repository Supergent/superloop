/**
 * Liquid Interface Version Storage
 *
 * Provides versioned storage for UITree views, enabling:
 * - Design history tracking
 * - Version comparison
 * - Rollback to previous versions
 * - Provenance (linking views to prompts/context that created them)
 *
 * Storage structure:
 * .superloop/ui/liquid/
 *   └── <view-name>/
 *       ├── versions/
 *       │   ├── 20240102-143022.json
 *       │   └── 20240102-144533.json
 *       └── meta.json
 */

import fs from "node:fs/promises";
import path from "node:path";

import type { UITree } from "@json-render/core";
import { fileExists, readJson } from "../lib/fs-utils.js";

// Re-export types from storage-types.ts for backwards compatibility
export type { ViewVersion, ViewMeta, LiquidView } from "./storage-types.js";
import type { ViewVersion, ViewMeta, LiquidView } from "./storage-types.js";

// ===================
// Constants
// ===================

export const LIQUID_DIR = ".superloop/ui/liquid";
const VERSIONS_DIR = "versions";
const META_FILENAME = "meta.json";
const VERSION_EXTENSION = ".json";
const TIMESTAMP_PATTERN = /^(\d{8}-\d{6})/;
const SAFE_VIEW_NAME_PATTERN = /^[A-Za-z0-9][A-Za-z0-9_-]*$/;
const SAFE_VERSION_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;

// ===================
// Timestamp Utilities
// ===================

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
  return date.toISOString();
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

// ===================
// Path Utilities
// ===================

export function resolveLiquidRoot(repoRoot: string): string {
  return path.join(repoRoot, LIQUID_DIR);
}

function isValidViewName(viewName: string): boolean {
  return SAFE_VIEW_NAME_PATTERN.test(viewName);
}

function assertValidViewName(viewName: string): void {
  if (!isValidViewName(viewName)) {
    throw new Error(`Invalid view name: ${viewName}`);
  }
}

function assertValidVersionId(versionId: string): void {
  if (!SAFE_VERSION_ID_PATTERN.test(versionId)) {
    throw new Error(`Invalid version ID: ${versionId}`);
  }
}

function resolvePathWithin(baseDir: string, relativePath: string): string {
  const resolvedBase = path.resolve(baseDir);
  const resolvedPath = path.resolve(resolvedBase, relativePath);

  if (resolvedPath !== resolvedBase && !resolvedPath.startsWith(`${resolvedBase}${path.sep}`)) {
    throw new Error(`Path escapes base directory: ${relativePath}`);
  }

  return resolvedPath;
}

export function resolveViewDir(repoRoot: string, viewName: string): string {
  assertValidViewName(viewName);
  return resolvePathWithin(resolveLiquidRoot(repoRoot), viewName);
}

export function resolveVersionsDir(repoRoot: string, viewName: string): string {
  return path.join(resolveViewDir(repoRoot, viewName), VERSIONS_DIR);
}

// ===================
// Core Operations
// ===================

/**
 * List all liquid views with their versions
 */
export async function listViews(repoRoot: string): Promise<LiquidView[]> {
  const root = resolveLiquidRoot(repoRoot);

  if (!(await fileExists(root))) {
    return [];
  }

  const entries = await fs.readdir(root, { withFileTypes: true });
  const views: LiquidView[] = [];

  for (const entry of entries) {
    if (entry.isDirectory() && isValidViewName(entry.name)) {
      const view = await loadView({ repoRoot, viewName: entry.name });
      if (view) {
        views.push(view);
      }
    }
  }

  return views.sort((a, b) => a.name.localeCompare(b.name));
}

/**
 * Load a specific view with all its versions
 */
export async function loadView(params: {
  repoRoot: string;
  viewName: string;
}): Promise<LiquidView | null> {
  const { repoRoot, viewName } = params;
  const viewDir = resolveViewDir(repoRoot, viewName);

  if (!(await fileExists(viewDir))) {
    return null;
  }

  // Load metadata
  const metaPath = path.join(viewDir, META_FILENAME);
  const meta = await readJson<ViewMeta>(metaPath);

  if (!meta) {
    return null;
  }

  // Load all versions
  const versionsDir = resolveVersionsDir(repoRoot, viewName);
  const versions: ViewVersion[] = [];

  if (await fileExists(versionsDir)) {
    const entries = await fs.readdir(versionsDir, { withFileTypes: true });

    for (const entry of entries) {
      if (entry.isFile() && entry.name.endsWith(VERSION_EXTENSION)) {
        const version = await loadVersionFile(
          path.join(versionsDir, entry.name),
          entry.name,
          meta,
        );
        if (version) {
          versions.push(version);
        }
      }
    }
  }

  if (versions.length === 0) {
    return null;
  }

  // Sort by creation time (oldest first)
  versions.sort((a, b) => a.createdAt.localeCompare(b.createdAt));

  const latest = versions[versions.length - 1];

  // Determine active version
  const activeId = meta.activeVersion;
  const active = activeId ? versions.find((v) => v.id === activeId) ?? latest : latest;

  return {
    name: viewName,
    description: meta.description,
    versions,
    latest,
    active,
    meta,
  };
}

/**
 * Load the latest/active UITree for a view
 */
export async function loadActiveTree(params: {
  repoRoot: string;
  viewName: string;
}): Promise<UITree | null> {
  const view = await loadView(params);
  return view?.active.tree ?? null;
}

/**
 * Save a new version of a view
 */
export async function saveVersion(params: {
  repoRoot: string;
  viewName: string;
  tree: UITree;
  prompt?: string;
  description?: string;
  parentVersion?: string;
}): Promise<ViewVersion> {
  const { repoRoot, viewName, tree, prompt, description, parentVersion } = params;

  // Ensure directories exist
  const viewDir = resolveViewDir(repoRoot, viewName);
  const versionsDir = resolveVersionsDir(repoRoot, viewName);
  await fs.mkdir(versionsDir, { recursive: true });

  // Generate version ID and filename
  const now = new Date();
  const versionId = createTimestampId(now);
  const filename = `${versionId}${VERSION_EXTENSION}`;
  const versionPath = path.join(versionsDir, filename);

  // Write the tree file
  await fs.writeFile(versionPath, JSON.stringify(tree, null, 2), "utf8");

  // Update metadata
  const metaPath = path.join(viewDir, META_FILENAME);
  const existingMeta = await readJson<ViewMeta>(metaPath);
  const nowIso = formatTimestamp(now);

  const meta: ViewMeta = {
    name: viewName,
    description: description ?? existingMeta?.description,
    activeVersion: null, // Latest is active by default
    createdAt: existingMeta?.createdAt ?? nowIso,
    updatedAt: nowIso,
    versions: [
      ...(existingMeta?.versions ?? []),
      {
        id: versionId,
        prompt,
        createdAt: nowIso,
        parentVersion,
      },
    ],
  };

  await fs.writeFile(metaPath, JSON.stringify(meta, null, 2), "utf8");

  return {
    id: versionId,
    filename,
    path: versionPath,
    createdAt: nowIso,
    tree,
    prompt,
  };
}

/**
 * Set the active version for a view
 */
export async function setActiveVersion(params: {
  repoRoot: string;
  viewName: string;
  versionId: string | null; // null = use latest
}): Promise<void> {
  const { repoRoot, viewName, versionId } = params;
  const metaPath = path.join(resolveViewDir(repoRoot, viewName), META_FILENAME);

  const meta = await readJson<ViewMeta>(metaPath);
  if (!meta) {
    throw new Error(`View not found: ${viewName}`);
  }

  // Validate version exists if specified
  if (versionId) {
    assertValidVersionId(versionId);
  }
  if (versionId && !meta.versions.some((v) => v.id === versionId)) {
    throw new Error(`Version not found: ${versionId}`);
  }

  meta.activeVersion = versionId;
  meta.updatedAt = formatTimestamp(new Date());

  await fs.writeFile(metaPath, JSON.stringify(meta, null, 2), "utf8");
}

/**
 * Load a specific version by ID
 */
export async function loadVersion(params: {
  repoRoot: string;
  viewName: string;
  versionId: string;
}): Promise<ViewVersion | null> {
  const { repoRoot, viewName, versionId } = params;
  assertValidVersionId(versionId);

  const view = await loadView({ repoRoot, viewName });
  if (!view) {
    return null;
  }

  return view.versions.find((v) => v.id === versionId) ?? null;
}

/**
 * Delete a specific version
 */
export async function deleteVersion(params: {
  repoRoot: string;
  viewName: string;
  versionId: string;
}): Promise<void> {
  const { repoRoot, viewName, versionId } = params;
  assertValidVersionId(versionId);

  const versionsDir = resolveVersionsDir(repoRoot, viewName);
  const filename = `${versionId}${VERSION_EXTENSION}`;
  const versionPath = path.join(versionsDir, filename);

  if (await fileExists(versionPath)) {
    await fs.unlink(versionPath);
  }

  // Update metadata
  const metaPath = path.join(resolveViewDir(repoRoot, viewName), META_FILENAME);
  const meta = await readJson<ViewMeta>(metaPath);

  if (meta) {
    meta.versions = meta.versions.filter((v) => v.id !== versionId);

    // If deleted version was active, reset to latest
    if (meta.activeVersion === versionId) {
      meta.activeVersion = null;
    }

    meta.updatedAt = formatTimestamp(new Date());
    await fs.writeFile(metaPath, JSON.stringify(meta, null, 2), "utf8");
  }
}

/**
 * Delete an entire view and all its versions
 */
export async function deleteView(params: {
  repoRoot: string;
  viewName: string;
}): Promise<void> {
  const { repoRoot, viewName } = params;
  const viewDir = resolveViewDir(repoRoot, viewName);

  if (await fileExists(viewDir)) {
    await fs.rm(viewDir, { recursive: true });
  }
}

// ===================
// Helpers
// ===================

async function loadVersionFile(
  filePath: string,
  filename: string,
  meta: ViewMeta,
): Promise<ViewVersion | null> {
  const tree = await readJson<UITree>(filePath);
  if (!tree || !tree.root || !tree.elements) {
    return null;
  }

  const versionId = extractVersionId(filename);
  const versionMeta = meta.versions.find((v) => v.id === versionId);

  // Get creation time from metadata or parse from filename
  const createdAt =
    versionMeta?.createdAt ??
    formatTimestamp(parseTimestampId(versionId) ?? new Date());

  return {
    id: versionId,
    filename,
    path: filePath,
    createdAt,
    tree,
    prompt: versionMeta?.prompt,
  };
}

function extractVersionId(filename: string): string {
  const match = filename.match(TIMESTAMP_PATTERN);
  return match?.[1] ?? path.basename(filename, VERSION_EXTENSION);
}
