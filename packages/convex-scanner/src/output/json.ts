/**
 * JSON output formatter
 */

import type { ScanResult } from '../types.js';

/**
 * Format scan results as JSON
 */
export function formatJson(result: ScanResult): string {
  return JSON.stringify(result, null, 2);
}
