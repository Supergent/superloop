/**
 * Static scanner - main orchestrator
 */

import { resolve } from 'node:path';
import type { ScanOptions, ScanResult, Finding, ScanError } from '../types.js';
import { loadConfig } from '../config/loader.js';
import { discoverFiles, normalizeConvexDirs } from './file-discovery.js';
import { ConvexParser } from '../parser/convex-parser.js';
import { RuleRegistry } from '../rules/registry.js';
import type { RuleContext } from '../rules/rule.js';

/**
 * Scan Convex code for security issues
 */
export async function scanConvex(
  projectPath: string,
  options: ScanOptions = {}
): Promise<ScanResult> {
  const startTime = Date.now();
  const throwOnError = options.throwOnError !== false; // default to true
  const errors: ScanError[] = [];

  // Helper to handle errors based on throwOnError setting
  const handleError = (error: unknown, context: string): void => {
    const errorObj = {
      file: context,
      message: error instanceof Error ? error.message : String(error),
      stack: error instanceof Error ? error.stack : undefined,
    };

    if (throwOnError) {
      throw error;
    } else {
      errors.push(errorObj);
    }
  };

  let config;
  try {
    // Load configuration
    config = await loadConfig(projectPath, options.configPath);
  } catch (error) {
    handleError(error, 'config-loading');
    // Return early with error
    return {
      findings: [],
      scannedFiles: [],
      errors,
      metadata: {
        timestamp: new Date().toISOString(),
        filesScanned: 0,
        filesWithFindings: 0,
        rulesRun: [],
        scannerVersion: '0.1.0',
        durationMs: Date.now() - startTime,
      },
    };
  }

  // Override config with options
  const convexDir = options.convexDir ?? config.convexDir;
  const ignorePatterns = options.ignore
    ? [...config.ignore, ...options.ignore]
    : config.ignore;

  let convexDirs: string[];
  try {
    // Normalize directory paths
    convexDirs = normalizeConvexDirs(projectPath, convexDir);
  } catch (error) {
    handleError(error, 'directory-normalization');
    return {
      findings: [],
      scannedFiles: [],
      errors,
      metadata: {
        timestamp: new Date().toISOString(),
        filesScanned: 0,
        filesWithFindings: 0,
        rulesRun: [],
        scannerVersion: '0.1.0',
        durationMs: Date.now() - startTime,
      },
    };
  }

  let files: string[];
  try {
    // Discover files
    files = await discoverFiles(convexDirs, ignorePatterns);
  } catch (error) {
    handleError(error, 'file-discovery');
    return {
      findings: [],
      scannedFiles: [],
      errors,
      metadata: {
        timestamp: new Date().toISOString(),
        filesScanned: 0,
        filesWithFindings: 0,
        rulesRun: [],
        scannerVersion: '0.1.0',
        durationMs: Date.now() - startTime,
      },
    };
  }

  if (files.length === 0) {
    return {
      findings: [],
      scannedFiles: [],
      errors: [],
      metadata: {
        timestamp: new Date().toISOString(),
        filesScanned: 0,
        filesWithFindings: 0,
        rulesRun: [],
        scannerVersion: '0.1.0',
        durationMs: Date.now() - startTime,
      },
    };
  }

  // Initialize parser
  const parser = new ConvexParser(files);

  // Initialize rule registry
  const registry = new RuleRegistry();

  // Apply configuration
  const rulesConfig = { ...config.rules, ...options.rules };
  registry.applyConfig(rulesConfig);

  const enabledRules = registry.getEnabledRules();

  // Scan files
  const allFindings: Finding[] = [];
  const scannedFiles: string[] = [];

  for (const file of files) {
    try {
      const functions = parser.parseFile(file);
      scannedFiles.push(file);

      // Run rules on each function
      for (const func of functions) {
        const context: RuleContext = {
          function: func,
          typeChecker: parser.getTypeChecker(),
          program: parser.getProgram(),
        };

        for (const { rule, config: ruleConfig } of enabledRules) {
          const findings = rule.check(context);

          // Apply severity override if configured
          for (const finding of findings) {
            if (ruleConfig.severity) {
              finding.severity = ruleConfig.severity;
            }
            allFindings.push(finding);
          }
        }
      }
    } catch (error) {
      errors.push({
        file,
        message: error instanceof Error ? error.message : String(error),
        stack: error instanceof Error ? error.stack : undefined,
      });
    }
  }

  // Calculate metadata
  const filesWithFindings = new Set(allFindings.map((f) => f.file)).size;
  const rulesRun = enabledRules.map((r) => r.rule.id);

  return {
    findings: allFindings,
    scannedFiles,
    errors,
    metadata: {
      timestamp: new Date().toISOString(),
      filesScanned: scannedFiles.length,
      filesWithFindings,
      rulesRun,
      scannerVersion: '0.1.0',
      durationMs: Date.now() - startTime,
    },
  };
}
