/**
 * Mole CLI wrapper functions
 * Executes Mole commands via Tauri shell API and returns parsed results
 */

import { invoke } from '@tauri-apps/api/core';
import { Command } from '@tauri-apps/plugin-shell';
import type {
  MoleStatusMetrics,
  MoleAnalyzeResult,
  MoleCleanResult,
  MoleUninstallResult,
  MoleOptimizeResult,
  MolePurgeResult,
  MoleInstallerResult,
  MoleError,
} from './moleTypes';
import {
  parseStatusJson,
  parseAnalyzeOutput,
  parseCleanOutput,
  parseUninstallOutput,
  parseOptimizeOutput,
  parsePurgeOutput,
  parseInstallerOutput,
  hasError,
  extractErrorMessage,
} from './moleParsers';

// ============================================================================
// Ensure Mole is installed
// ============================================================================

/**
 * Ensures the Mole binary is installed in ~/Library/Application Support/Valet/bin
 * This is called automatically on app startup
 */
export async function ensureMoleInstalled(): Promise<string> {
  try {
    const path = await invoke<string>('ensure_mole_installed_command');
    return path;
  } catch (error) {
    throw createMoleError('ensure_mole_installed', error);
  }
}

// ============================================================================
// Execute Mole command
// ============================================================================

interface CommandResult {
  stdout: string;
  stderr: string;
  code: number;
}

async function executeMoleCommand(args: string[]): Promise<CommandResult> {
  // Use the 'mo' command name as defined in capabilities allowlist
  // Prepend the Valet App Support bin directory to PATH so the bundled binary is found
  const home = await invoke<string>('get_home_dir');
  const valetBinDir = `${home}/Library/Application Support/Valet/bin`;
  const currentPath = (typeof process !== 'undefined' && process.env?.PATH) || '/usr/local/bin:/usr/bin:/bin';
  const updatedPath = `${valetBinDir}:${currentPath}`;

  const command = Command.create('mo', args, {
    env: {
      PATH: updatedPath,
    },
  });

  const output = await command.execute();

  return {
    stdout: output.stdout,
    stderr: output.stderr,
    code: output.code,
  };
}

// ============================================================================
// mo status --json
// ============================================================================

export async function getSystemStatus(): Promise<MoleStatusMetrics> {
  try {
    const result = await executeMoleCommand(['status', '--json']);

    if (result.code !== 0 || hasError(result.stderr)) {
      throw new Error(extractErrorMessage(result.stderr || result.stdout));
    }

    return parseStatusJson(result.stdout);
  } catch (error) {
    throw createMoleError('status', error);
  }
}

// ============================================================================
// mo analyze
// ============================================================================

export async function analyzeDiskUsage(path?: string): Promise<MoleAnalyzeResult> {
  try {
    const args = ['analyze'];
    if (path) {
      args.push(path);
    }

    const result = await executeMoleCommand(args);

    if (result.code !== 0 || hasError(result.stderr)) {
      throw new Error(extractErrorMessage(result.stderr || result.stdout));
    }

    return parseAnalyzeOutput(result.stdout);
  } catch (error) {
    throw createMoleError('analyze', error);
  }
}

// ============================================================================
// mo clean
// ============================================================================

export async function cleanSystem(options?: { dryRun?: boolean }): Promise<MoleCleanResult> {
  try {
    const args = ['clean'];
    const isDryRun = options?.dryRun !== false; // Default to dry run for safety

    if (isDryRun) {
      args.push('--dry-run');
    }

    const result = await executeMoleCommand(args);

    if (result.code !== 0 || hasError(result.stderr)) {
      throw new Error(extractErrorMessage(result.stderr || result.stdout));
    }

    return parseCleanOutput(result.stdout, isDryRun);
  } catch (error) {
    throw createMoleError('clean', error);
  }
}

// ============================================================================
// mo uninstall
// ============================================================================

export async function uninstallApp(appName: string): Promise<MoleUninstallResult> {
  try {
    const result = await executeMoleCommand(['uninstall', appName]);

    // Uninstall might have non-zero exit code but still partially succeed
    return parseUninstallOutput(appName, result.stdout + '\n' + result.stderr);
  } catch (error) {
    throw createMoleError('uninstall', error);
  }
}

// ============================================================================
// mo optimize
// ============================================================================

/**
 * Run mo optimize with admin privileges using osascript prompt
 * This should be used when optimize requires sudo access
 */
export async function optimizeSystemPrivileged(options?: { dryRun?: boolean }): Promise<MoleOptimizeResult> {
  try {
    const isDryRun = options?.dryRun !== false; // Default to dry run for safety
    const output = await invoke<string>('run_privileged_optimize', { dryRun: isDryRun });
    return parseOptimizeOutput(output, isDryRun);
  } catch (error) {
    throw createMoleError('optimize (privileged)', error);
  }
}

/**
 * Run mo optimize - always uses privileged execution for consistency
 * Delegates to optimizeSystemPrivileged
 */
export async function optimizeSystem(options?: { dryRun?: boolean }): Promise<MoleOptimizeResult> {
  return optimizeSystemPrivileged(options);
}

// ============================================================================
// mo purge
// ============================================================================

export async function purgeDeveloperArtifacts(options?: {
  dryRun?: boolean;
}): Promise<MolePurgeResult> {
  try {
    const args = ['purge'];
    const isDryRun = options?.dryRun !== false; // Default to dry run for safety

    if (isDryRun) {
      args.push('--dry-run');
    }

    const result = await executeMoleCommand(args);

    if (result.code !== 0 || hasError(result.stderr)) {
      throw new Error(extractErrorMessage(result.stderr || result.stdout));
    }

    return parsePurgeOutput(result.stdout, isDryRun);
  } catch (error) {
    throw createMoleError('purge', error);
  }
}

// ============================================================================
// mo installer
// ============================================================================

export async function cleanupInstallers(options?: {
  dryRun?: boolean;
}): Promise<MoleInstallerResult> {
  try {
    const args = ['installer'];
    const isDryRun = options?.dryRun !== false; // Default to dry run for safety

    if (isDryRun) {
      args.push('--dry-run');
    }

    const result = await executeMoleCommand(args);

    if (result.code !== 0 || hasError(result.stderr)) {
      throw new Error(extractErrorMessage(result.stderr || result.stdout));
    }

    return parseInstallerOutput(result.stdout, isDryRun);
  } catch (error) {
    throw createMoleError('installer', error);
  }
}

// ============================================================================
// Helper functions
// ============================================================================

function createMoleError(command: string, error: unknown): MoleError {
  const message = error instanceof Error ? error.message : 'Unknown error';
  const stderr = error instanceof Error ? error.stack : undefined;

  return {
    command,
    message,
    stderr,
  };
}

// ============================================================================
// Exports
// ============================================================================

export const mole = {
  ensureInstalled: ensureMoleInstalled,
  getSystemStatus,
  analyzeDiskUsage,
  cleanSystem,
  uninstallApp,
  optimizeSystem,
  optimizeSystemPrivileged,
  purgeDeveloperArtifacts,
  cleanupInstallers,
};

export default mole;
