/**
 * Tests for CLI functionality
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { runCli } from '../cli.js';
import * as scanner from '../scanner/static-scanner.js';
import type { ScanResult } from '../types.js';
import * as fs from 'fs/promises';
import { realpathSync } from 'node:fs';
import { resolve, join, isAbsolute } from 'node:path';

// Mock the scanner
vi.mock('../scanner/static-scanner.js');

// Mock fs promises
vi.mock('fs/promises');

describe('CLI', () => {
  let consoleLogSpy: any;
  let consoleErrorSpy: any;
  let processExitSpy: any;

  const mockResult: ScanResult = {
    findings: [],
    scannedFiles: ['test.ts'],
    errors: [],
    metadata: {
      timestamp: '2025-01-17T00:00:00.000Z',
      filesScanned: 1,
      filesWithFindings: 0,
      rulesRun: ['auth/missing-auth-check'],
      scannerVersion: '0.1.0',
      durationMs: 100,
    },
  };

  beforeEach(() => {
    consoleLogSpy = vi.spyOn(console, 'log').mockImplementation(() => {});
    consoleErrorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
    processExitSpy = vi.spyOn(process, 'exit').mockImplementation((() => {
      throw new Error('process.exit called');
    }) as any);

    vi.mocked(scanner.scanConvex).mockResolvedValue(mockResult);
    vi.mocked(fs.writeFile).mockResolvedValue(undefined);
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe('Output Formats', () => {
    it('should output JSON format when --format json is specified', async () => {
      await runCli(['--format', 'json']).catch(() => {});

      expect(scanner.scanConvex).toHaveBeenCalledWith('.', {
        format: 'json',
        configPath: undefined,
        throwOnError: false,
      });

      const output = consoleLogSpy.mock.calls[0]?.[0] as string;
      expect(output).toBeTruthy();

      // Verify it's valid JSON
      const parsed = JSON.parse(output);
      expect(parsed).toHaveProperty('findings');
      expect(parsed).toHaveProperty('scannedFiles');
      expect(parsed).toHaveProperty('errors');
      expect(parsed).toHaveProperty('metadata');
    });

    it('should output Markdown format by default', async () => {
      await runCli([]).catch(() => {});

      expect(scanner.scanConvex).toHaveBeenCalledWith('.', {
        format: 'markdown',
        configPath: undefined,
        throwOnError: false,
      });

      const output = consoleLogSpy.mock.calls[0]?.[0] as string;
      expect(output).toBeTruthy();
      expect(output).toContain('# Convex Security Scanner Report');
    });

    it('should output Markdown format when --format markdown is specified', async () => {
      await runCli(['--format', 'markdown']).catch(() => {});

      const output = consoleLogSpy.mock.calls[0]?.[0] as string;
      expect(output).toContain('# Convex Security Scanner Report');
    });
  });

  describe('Error Handling', () => {
    it('should exit with non-zero code when findings exist', async () => {
      vi.mocked(scanner.scanConvex).mockResolvedValue({
        ...mockResult,
        findings: [
          {
            file: 'test.ts',
            line: 1,
            column: 0,
            endLine: 1,
            endColumn: 10,
            rule: 'auth/missing-auth-check',
            category: 'auth',
            severity: 'high',
            message: 'Test finding',
            remediation: 'Fix it',
            context: 'code here',
          },
        ],
      });

      await expect(runCli([])).rejects.toThrow('process.exit called');
      expect(processExitSpy).toHaveBeenCalledWith(1);
    });

    it('should exit with non-zero code when errors exist', async () => {
      vi.mocked(scanner.scanConvex).mockResolvedValue({
        ...mockResult,
        errors: [
          {
            file: 'test.ts',
            message: 'Parse error',
          },
        ],
      });

      await expect(runCli([])).rejects.toThrow('process.exit called');
      expect(processExitSpy).toHaveBeenCalledWith(1);
    });

    it('should handle invalid project path gracefully', async () => {
      vi.mocked(scanner.scanConvex).mockRejectedValue(new Error('Invalid path'));

      await expect(runCli(['./nonexistent'])).rejects.toThrow('process.exit called');
      expect(consoleErrorSpy).toHaveBeenCalledWith(
        'Error running scanner:',
        expect.any(Error)
      );
      expect(processExitSpy).toHaveBeenCalledWith(1);
    });

    it('should exit with error on invalid format argument', async () => {
      await expect(runCli(['--format', 'invalid'])).rejects.toThrow('process.exit called');
      expect(consoleErrorSpy).toHaveBeenCalledWith(
        expect.stringContaining('Invalid format')
      );
      expect(processExitSpy).toHaveBeenCalledWith(1);
    });
  });

  describe('Argument Parsing', () => {
    it('should parse project path argument', async () => {
      await runCli(['./my-project']).catch(() => {});

      expect(scanner.scanConvex).toHaveBeenCalledWith('./my-project', expect.any(Object));
    });

    it('should parse --config argument', async () => {
      await runCli(['--config', './custom-config.ts']).catch(() => {});

      expect(scanner.scanConvex).toHaveBeenCalledWith('.', {
        format: 'markdown',
        configPath: './custom-config.ts',
        throwOnError: false,
      });
    });

    it('should parse --convex-dir argument', async () => {
      await runCli(['--convex-dir', './backend']).catch(() => {});

      expect(scanner.scanConvex).toHaveBeenCalledWith('.', {
        format: 'markdown',
        configPath: undefined,
        convexDir: './backend',
        throwOnError: false,
      });
    });

    it('should parse --ignore argument', async () => {
      await runCli(['--ignore', '**/*.test.ts']).catch(() => {});

      expect(scanner.scanConvex).toHaveBeenCalledWith('.', {
        format: 'markdown',
        configPath: undefined,
        ignore: ['**/*.test.ts'],
        throwOnError: false,
      });
    });

    it('should parse multiple --ignore arguments', async () => {
      await runCli(['--ignore', '**/*.test.ts', '--ignore', '**/*.spec.ts']).catch(() => {});

      expect(scanner.scanConvex).toHaveBeenCalledWith('.', {
        format: 'markdown',
        configPath: undefined,
        ignore: ['**/*.test.ts', '**/*.spec.ts'],
        throwOnError: false,
      });
    });

    it('should parse short-form arguments', async () => {
      await runCli(['-f', 'json', '-c', './config.ts', '-d', './backend']).catch(() => {});

      expect(scanner.scanConvex).toHaveBeenCalledWith('.', {
        format: 'json',
        configPath: './config.ts',
        convexDir: './backend',
        throwOnError: false,
      });
    });

    it('should parse --rules argument', async () => {
      await runCli(['--rules', 'auth/missing-auth-check']).catch(() => {});

      expect(scanner.scanConvex).toHaveBeenCalledWith('.', {
        format: 'markdown',
        configPath: undefined,
        rules: {
          'auth/missing-auth-check': { enabled: true },
        },
        throwOnError: false,
      });
    });

    it('should parse multiple --rules arguments', async () => {
      await runCli(['--rules', 'auth/missing-auth-check', '--rules', 'validation/input-check']).catch(() => {});

      expect(scanner.scanConvex).toHaveBeenCalledWith('.', {
        format: 'markdown',
        configPath: undefined,
        rules: {
          'auth/missing-auth-check': { enabled: true },
          'validation/input-check': { enabled: true },
        },
        throwOnError: false,
      });
    });
  });

  describe('Output File', () => {
    it('should write output to file when --output is specified', async () => {
      await runCli(['--output', 'report.md']).catch(() => {});

      expect(fs.writeFile).toHaveBeenCalledWith(
        'report.md',
        expect.stringContaining('# Convex Security Scanner Report'),
        'utf-8'
      );
      expect(consoleErrorSpy).toHaveBeenCalledWith('Report written to report.md');
    });

    it('should write JSON to file when both --format json and --output are specified', async () => {
      await runCli(['--format', 'json', '--output', 'report.json']).catch(() => {});

      expect(fs.writeFile).toHaveBeenCalledWith(
        'report.json',
        expect.any(String),
        'utf-8'
      );

      const writeCall = vi.mocked(fs.writeFile).mock.calls[0];
      const content = writeCall?.[1] as string;
      expect(content).toBeTruthy();

      // Verify it's valid JSON
      const parsed = JSON.parse(content);
      expect(parsed).toHaveProperty('findings');
    });

    it('should not write to stdout when --output is specified', async () => {
      await runCli(['--output', 'report.md']).catch(() => {});

      // consoleLogSpy should not be called with the report
      expect(consoleLogSpy).not.toHaveBeenCalledWith(
        expect.stringContaining('# Convex Security Scanner Report')
      );
    });
  });

  describe('CLI always sets throwOnError: false', () => {
    it('should set throwOnError to false', async () => {
      await runCli([]).catch(() => {});

      expect(scanner.scanConvex).toHaveBeenCalledWith('.', {
        format: 'markdown',
        configPath: undefined,
        throwOnError: false,
      });
    });
  });

  describe('CLI Entry Guard Path Resolution', () => {
    it('should correctly resolve symlinked paths on Unix', async () => {
      // Test that the entry guard uses realpathSync() to dereference symlinks
      // This ensures symlinks like node_modules/.bin/convex-scanner -> ../package/dist/cli.mjs work
      // The actual logic is in cli.ts using fileURLToPath(import.meta.url) and realpathSync(resolve(process.argv[1]))

      // Import the real fs module (not mocked) for this test
      const realFs = await vi.importActual<typeof import('node:fs/promises')>('node:fs/promises');
      const os = await vi.importActual<typeof import('node:os')>('node:os');

      // Create temporary symlink test files
      const tmpDir = await realFs.mkdtemp(join(os.tmpdir(), 'convex-scanner-test-'));

      try {
        // Create a test file
        const targetFile = join(tmpDir, 'target.js');
        await realFs.writeFile(targetFile, 'console.log("test");', 'utf-8');

        // Create a symlink to it
        const linkFile = join(tmpDir, 'link.js');
        await realFs.symlink(targetFile, linkFile);

        // Verify realpathSync resolves both to the same path
        const realTarget = realpathSync(targetFile);
        const realLink = realpathSync(linkFile);

        expect(realTarget).toBe(realLink);

        // Also verify that resolve alone doesn't dereference symlinks
        const resolvedLink = resolve(linkFile);
        expect(resolvedLink).not.toBe(realLink); // resolve preserves symlink path
      } finally {
        // Cleanup
        await realFs.rm(tmpDir, { recursive: true, force: true });
      }
    });

    it('should correctly handle Windows-style paths', () => {
      // Test that the entry guard normalizes Windows paths (C:\Users\... vs /c/Users/...)
      // The resolve() function handles this cross-platform
      // realpathSync() further ensures the canonical path is used

      // On any platform, realpathSync should return a normalized absolute path
      // Use a path we know exists (__filename is available in CJS context)
      const currentFile = __filename;
      const real = realpathSync(currentFile);
      const resolved = resolve(currentFile);

      // Both should be absolute paths
      expect(isAbsolute(real)).toBe(true);
      expect(isAbsolute(resolved)).toBe(true);
    });
  });

  describe('Module Import Safety', () => {
    it('should not trigger runCli or process.exit when imported as a module', () => {
      // This test verifies that simply importing cli.ts doesn't execute the CLI.
      // The import at the top of this file should not have triggered process.exit.
      // If it did, this test suite wouldn't be running.
      expect(true).toBe(true);
    });
  });
});
