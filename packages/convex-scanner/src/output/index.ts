/**
 * Output formatter exports
 */

export { formatJson } from './json.js';
export { formatMarkdown } from './markdown.js';

import type { ScanResult } from '../types.js';
import { formatJson } from './json.js';
import { formatMarkdown } from './markdown.js';

/**
 * Format scan results based on requested format
 */
export function formatOutput(
  result: ScanResult,
  format: 'json' | 'markdown' = 'json'
): string {
  switch (format) {
    case 'json':
      return formatJson(result);
    case 'markdown':
      return formatMarkdown(result);
    default:
      return formatJson(result);
  }
}
