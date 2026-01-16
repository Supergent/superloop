/**
 * Liquid Interface Storage Types
 *
 * Separated from storage.ts to allow browser imports without Node.js dependencies.
 */

import type { UITree } from "@json-render/core";

export interface ViewVersion {
  /** Unique identifier (timestamp-based) */
  id: string;
  /** Filename in versions directory */
  filename: string;
  /** Full path to version file */
  path: string;
  /** Human-readable creation timestamp */
  createdAt: string;
  /** The UITree content */
  tree: UITree;
  /** Optional prompt that generated this version */
  prompt?: string;
}

export interface ViewMeta {
  /** View name */
  name: string;
  /** Human description of the view */
  description?: string;
  /** Currently active version ID (null = latest) */
  activeVersion?: string | null;
  /** First created timestamp */
  createdAt: string;
  /** Last updated timestamp */
  updatedAt: string;
  /** Version history with prompts */
  versions: Array<{
    id: string;
    prompt?: string;
    createdAt: string;
    parentVersion?: string;
  }>;
}

export interface LiquidView {
  /** View name (directory name) */
  name: string;
  /** View description */
  description?: string;
  /** All versions (oldest to newest) */
  versions: ViewVersion[];
  /** The latest version */
  latest: ViewVersion;
  /** Currently active version (may differ from latest) */
  active: ViewVersion;
  /** Metadata */
  meta: ViewMeta;
}
