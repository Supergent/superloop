/**
 * Configuration loader
 */

import { existsSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { createJiti } from 'jiti';
import { configSchema, type ScannerConfig } from './schema.js';
import { DEFAULT_CONFIG, DEFAULT_IGNORE_PATTERNS } from './defaults.js';

/**
 * Load and validate scanner configuration
 */
export async function loadConfig(
  projectPath: string,
  configPath?: string
): Promise<Required<ScannerConfig>> {
  let userConfig: Partial<ScannerConfig> = {};

  // Try to find and load config file
  const configFilePath = configPath
    ? resolve(projectPath, configPath)
    : findConfigFile(projectPath);

  if (configFilePath && existsSync(configFilePath)) {
    try {
      let rawConfig: unknown;

      // Use jiti for .ts files, dynamic import for .js/.mjs
      if (configFilePath.endsWith('.ts')) {
        const jiti = createJiti(projectPath, {
          interopDefault: true,
          requireCache: false,
        });
        rawConfig = jiti(configFilePath);
      } else {
        const configModule = await import(pathToFileURL(configFilePath).href);
        rawConfig = configModule.default || configModule;
      }

      // Validate config against schema
      const parsed = configSchema.parse(rawConfig);
      userConfig = parsed;
    } catch (error) {
      throw new Error(
        `Failed to load config from ${configFilePath}: ${
          error instanceof Error ? error.message : String(error)
        }`
      );
    }
  }

  // Merge with defaults
  return mergeConfig(DEFAULT_CONFIG, userConfig);
}

/**
 * Find config file in project directory
 */
function findConfigFile(projectPath: string): string | null {
  const possiblePaths = [
    join(projectPath, 'convex-scanner.config.ts'),
    join(projectPath, 'convex-scanner.config.js'),
    join(projectPath, 'convex-scanner.config.mjs'),
  ];

  for (const path of possiblePaths) {
    if (existsSync(path)) {
      return path;
    }
  }

  return null;
}

/**
 * Merge user config with defaults
 */
function mergeConfig(
  defaults: Required<ScannerConfig>,
  user: Partial<ScannerConfig>
): Required<ScannerConfig> {
  return {
    convexDir: user.convexDir ?? defaults.convexDir,
    rules: { ...defaults.rules, ...user.rules },
    // When user provides custom ignore patterns, use them instead of defaults
    ignore: user.ignore ?? defaults.ignore,
  };
}
