/**
 * File discovery - finds Convex files to scan
 */

import fg from 'fast-glob';
import { resolve, join } from 'node:path';
import { existsSync } from 'node:fs';

/**
 * Discover Convex files to scan
 */
export async function discoverFiles(
  convexDirs: string | string[],
  ignorePatterns: string[]
): Promise<string[]> {
  const dirs = Array.isArray(convexDirs) ? convexDirs : [convexDirs];
  const allFiles: string[] = [];

  for (const dir of dirs) {
    if (!existsSync(dir)) {
      throw new Error(`Convex directory does not exist: ${dir}`);
    }

    const files = await fg(['**/*.ts', '**/*.tsx'], {
      cwd: dir,
      absolute: true,
      ignore: ignorePatterns,
    });

    allFiles.push(...files);
  }

  return allFiles;
}

/**
 * Normalize convex directory paths
 * Handles both project-root and direct convex-dir inputs
 */
export function normalizeConvexDirs(
  projectPath: string,
  convexDirs: string | string[]
): string[] {
  const dirs = Array.isArray(convexDirs) ? convexDirs : [convexDirs];
  return dirs.map((dir) => {
    const resolved = resolve(projectPath, dir);

    // If projectPath already points to a convex directory and dir is 'convex', use projectPath directly
    const projectPathIsConvexDir = projectPath.endsWith('/convex') || projectPath.endsWith('\\convex');
    if (projectPathIsConvexDir && (dir === 'convex' || dir === './convex')) {
      return resolve(projectPath);
    }

    // If path exists and doesn't end with 'convex', check if convex subdirectory exists
    if (existsSync(resolved) && !resolved.endsWith('/convex') && !resolved.endsWith('\\convex')) {
      const withConvex = join(resolved, 'convex');
      if (existsSync(withConvex)) {
        return withConvex;
      }
    }

    return resolved;
  });
}
