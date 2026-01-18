/**
 * Default configuration values
 */

import type { ScannerConfig } from './schema.js';

/**
 * Default ignore patterns
 */
export const DEFAULT_IGNORE_PATTERNS = [
  '**/node_modules/**',
  '**/.git/**',
  '**/dist/**',
  '**/build/**',
  '**/_generated/**',
];

/**
 * Default configuration
 */
export const DEFAULT_CONFIG: Required<ScannerConfig> = {
  convexDir: './convex',
  rules: {
    'auth/missing-auth-check': {
      enabled: true,
      severity: 'high',
      options: {
        checkQueries: true,
        checkMutations: true,
        checkActions: true,
        allowList: [],
        allowInlineSuppressions: true,
      },
    },
  },
  ignore: DEFAULT_IGNORE_PATTERNS,
};
