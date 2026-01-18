/**
 * Pattern matching helper for allowlists.
 */

import { minimatch } from 'minimatch';

export function matchesPattern(functionName: string, patterns: string[]): boolean {
  return patterns.some((pattern) =>
    minimatch(functionName, pattern, { nocase: true })
  );
}
