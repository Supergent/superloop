/**
 * Configuration schema for the Convex Scanner
 */

import { z } from 'zod';

/**
 * Schema for rule configuration
 */
export const ruleConfigSchema = z.object({
  enabled: z.boolean().optional(),
  severity: z.enum(['critical', 'high', 'medium', 'low', 'info']).optional(),
  options: z
    .object({
      checkQueries: z.boolean().optional().default(true),
      checkMutations: z.boolean().optional().default(true),
      checkActions: z.boolean().optional().default(true),
      allowList: z.array(z.string()).optional().default([]),
      allowInlineSuppressions: z.boolean().optional().default(true),
    })
    .optional(),
});

export type RuleConfig = z.infer<typeof ruleConfigSchema>;

/**
 * Schema for scanner configuration file
 */
export const configSchema = z.object({
  /**
   * Path to Convex directory (or multiple directories)
   */
  convexDir: z.union([z.string(), z.array(z.string())]).optional(),

  /**
   * Rule configuration (enable/disable, severity overrides)
   */
  rules: z.record(z.string(), ruleConfigSchema).optional(),

  /**
   * File/directory patterns to ignore
   */
  ignore: z.array(z.string()).optional(),
});

export type ScannerConfig = z.infer<typeof configSchema>;
