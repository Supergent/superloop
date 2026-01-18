/**
 * CLI entry point for Convex Security Scanner
 */

import { scanConvex } from './scanner/static-scanner.js';
import { formatJson } from './output/json.js';
import { formatMarkdown } from './output/markdown.js';
import type { ScanOptions } from './types.js';
import { fileURLToPath } from 'node:url';
import { resolve, dirname } from 'node:path';
import { realpathSync } from 'node:fs';

interface CliArgs {
  projectPath: string;
  format?: 'json' | 'markdown';
  config?: string;
  convexDir?: string;
  ignore?: string[];
  rules?: string[];
  output?: string;
}

/**
 * Parse command line arguments
 */
function parseArgs(args: string[]): CliArgs {
  const result: CliArgs = {
    projectPath: '.',
    format: 'markdown',
  };

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];

    if (!arg) continue;

    switch (arg) {
      case '--format':
      case '-f': {
        const formatValue = args[i + 1];
        if (formatValue === 'json' || formatValue === 'markdown') {
          result.format = formatValue;
          i++;
        } else {
          console.error(`Invalid format: ${formatValue ?? 'undefined'}. Use 'json' or 'markdown'.`);
          process.exit(1);
        }
        break;
      }
      case '--config':
      case '-c': {
        const configValue = args[i + 1];
        if (configValue) {
          result.config = configValue;
          i++;
        }
        break;
      }
      case '--convex-dir':
      case '-d': {
        const dirValue = args[i + 1];
        if (dirValue) {
          result.convexDir = dirValue;
          i++;
        }
        break;
      }
      case '--ignore': {
        const ignoreValue = args[i + 1];
        if (ignoreValue) {
          if (!result.ignore) result.ignore = [];
          result.ignore.push(ignoreValue);
          i++;
        }
        break;
      }
      case '--rules': {
        const rulesValue = args[i + 1];
        if (rulesValue) {
          if (!result.rules) result.rules = [];
          result.rules.push(rulesValue);
          i++;
        }
        break;
      }
      case '--output':
      case '-o': {
        const outputValue = args[i + 1];
        if (outputValue) {
          result.output = outputValue;
          i++;
        }
        break;
      }
      case '--help':
      case '-h': {
        printHelp();
        process.exit(0);
        break;
      }
      default: {
        // If it doesn't start with -, treat as project path
        if (!arg.startsWith('-')) {
          result.projectPath = arg;
        } else {
          console.error(`Unknown argument: ${arg}`);
          process.exit(1);
        }
        break;
      }
    }
  }

  return result;
}

/**
 * Print help message
 */
function printHelp(): void {
  console.log(`
Convex Security Scanner CLI

Usage: convex-scanner [projectPath] [options]

Arguments:
  projectPath              Path to project directory (default: current directory)

Options:
  --format, -f <format>    Output format: 'json' or 'markdown' (default: markdown)
  --config, -c <path>      Path to config file (default: auto-discover)
  --convex-dir, -d <path>  Path to Convex directory (default: ./convex)
  --ignore <pattern>       Ignore pattern (can be specified multiple times)
  --rules <rule>           Rule ID to enable (can be specified multiple times)
  --output, -o <path>      Output file path (default: stdout)
  --help, -h               Show this help message

Examples:
  convex-scanner                           # Scan current directory
  convex-scanner ./my-project              # Scan specific project
  convex-scanner --format json             # Output as JSON
  convex-scanner --convex-dir ./backend    # Custom Convex directory
  convex-scanner --output report.md        # Save to file
`);
}

/**
 * Main CLI execution
 */
export async function runCli(args: string[]): Promise<void> {
  const cliArgs = parseArgs(args);

  try {
    // Build scan options
    const options: ScanOptions = {
      format: cliArgs.format,
      configPath: cliArgs.config,
      throwOnError: false, // CLI should collect errors, not throw
    };

    if (cliArgs.convexDir) {
      options.convexDir = cliArgs.convexDir;
    }

    if (cliArgs.ignore) {
      options.ignore = cliArgs.ignore;
    }

    if (cliArgs.rules) {
      // Convert rule IDs array to rules config object
      options.rules = cliArgs.rules.reduce((acc, ruleId) => {
        acc[ruleId] = { enabled: true };
        return acc;
      }, {} as Record<string, { enabled: boolean }>);
    }

    // Run scan
    const result = await scanConvex(cliArgs.projectPath, options);

    // Format output
    let output: string;
    if (cliArgs.format === 'json') {
      output = formatJson(result);
    } else {
      output = formatMarkdown(result);
    }

    // Write output
    if (cliArgs.output) {
      const fs = await import('fs/promises');
      await fs.writeFile(cliArgs.output, output, 'utf-8');
      console.error(`Report written to ${cliArgs.output}`);
    } else {
      console.log(output);
    }

    // Exit with non-zero if errors or findings exist
    if (result.errors.length > 0 || result.findings.length > 0) {
      process.exit(1);
    }
  } catch (error) {
    console.error('Error running scanner:', error);
    process.exit(1);
  }
}

// Run CLI if executed directly (not imported as a module)
// This file is built as ESM-only (see tsup.config.ts), so import.meta is always available
// @ts-ignore - TypeScript doesn't know this file is ESM-only at compile time
const currentModulePath = realpathSync(fileURLToPath(import.meta.url));
const scriptPath = process.argv[1] ? realpathSync(resolve(process.argv[1])) : '';
if (currentModulePath === scriptPath) {
  const args = process.argv.slice(2);
  runCli(args).catch((error) => {
    console.error('Fatal error:', error);
    process.exit(1);
  });
}
