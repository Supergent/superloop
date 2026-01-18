import { describe, it, expect } from 'vitest';
import { formatMarkdown } from '../markdown.js';
import type { ScanResult } from '../../types.js';

describe('markdown formatter', () => {
  it('should format scan result as markdown', () => {
    const result: ScanResult = {
      findings: [
        {
          file: '/path/to/file.ts',
          line: 10,
          column: 5,
          endLine: 10,
          endColumn: 20,
          rule: 'auth/missing-auth-check',
          category: 'auth',
          severity: 'high',
          message: 'Mutation missing authentication check',
          remediation: 'Add ctx.auth check',
          context: 'export const myMutation = mutation({',
        },
      ],
      scannedFiles: ['/path/to/file.ts'],
      errors: [],
      metadata: {
        timestamp: '2025-01-01T00:00:00.000Z',
        filesScanned: 1,
        filesWithFindings: 1,
        rulesRun: ['auth/missing-auth-check'],
        scannerVersion: '0.1.0',
        durationMs: 100,
      },
    };

    const markdown = formatMarkdown(result);

    expect(markdown).toContain('# Convex Security Scanner Report');
    expect(markdown).toContain('## Summary');
    expect(markdown).toContain('**Files Scanned**: 1');
    expect(markdown).toContain('**Total Findings**: 1');
  });

  it('should include metadata section', () => {
    const result: ScanResult = {
      findings: [],
      scannedFiles: [],
      errors: [],
      metadata: {
        timestamp: '2025-01-01T12:30:00.000Z',
        filesScanned: 5,
        filesWithFindings: 2,
        rulesRun: ['auth/missing-auth-check', 'validation/weak-validator'],
        scannerVersion: '0.1.0',
        durationMs: 250,
      },
    };

    const markdown = formatMarkdown(result);

    expect(markdown).toContain('**Scan Time**: 2025-01-01T12:30:00.000Z');
    expect(markdown).toContain('**Duration**: 250ms');
    expect(markdown).toContain('**Files Scanned**: 5');
    expect(markdown).toContain('**Files with Findings**: 2');
  });

  it('should list rules executed', () => {
    const result: ScanResult = {
      findings: [],
      scannedFiles: [],
      errors: [],
      metadata: {
        timestamp: '2025-01-01T00:00:00.000Z',
        filesScanned: 0,
        filesWithFindings: 0,
        rulesRun: ['auth/missing-auth-check', 'validation/weak-validator'],
        scannerVersion: '0.1.0',
        durationMs: 50,
      },
    };

    const markdown = formatMarkdown(result);

    expect(markdown).toContain('## Rules Executed');
    expect(markdown).toContain('- auth/missing-auth-check');
    expect(markdown).toContain('- validation/weak-validator');
  });

  it('should group findings by severity', () => {
    const result: ScanResult = {
      findings: [
        {
          file: '/file1.ts',
          line: 10,
          column: 5,
          endLine: 10,
          endColumn: 20,
          rule: 'auth/missing-auth-check',
          category: 'auth',
          severity: 'critical',
          message: 'Critical issue',
          remediation: 'Fix it',
          context: 'code here',
        },
        {
          file: '/file2.ts',
          line: 20,
          column: 10,
          endLine: 20,
          endColumn: 25,
          rule: 'validation/weak',
          category: 'validation',
          severity: 'medium',
          message: 'Medium issue',
          remediation: 'Fix it too',
          context: 'more code',
        },
        {
          file: '/file3.ts',
          line: 30,
          column: 15,
          endLine: 30,
          endColumn: 30,
          rule: 'general/info',
          category: 'general',
          severity: 'critical',
          message: 'Another critical',
          remediation: 'Fix this',
          context: 'even more code',
        },
      ],
      scannedFiles: ['/file1.ts', '/file2.ts', '/file3.ts'],
      errors: [],
      metadata: {
        timestamp: '2025-01-01T00:00:00.000Z',
        filesScanned: 3,
        filesWithFindings: 3,
        rulesRun: ['auth/missing-auth-check', 'validation/weak', 'general/info'],
        scannerVersion: '0.1.0',
        durationMs: 150,
      },
    };

    const markdown = formatMarkdown(result);

    expect(markdown).toContain('### Critical (2)');
    expect(markdown).toContain('### Medium (1)');
    expect(markdown).toContain('Critical issue');
    expect(markdown).toContain('Medium issue');
  });

  it('should format individual findings with all details', () => {
    const result: ScanResult = {
      findings: [
        {
          file: '/path/to/file.ts',
          line: 42,
          column: 12,
          endLine: 42,
          endColumn: 30,
          rule: 'auth/missing-auth-check',
          category: 'auth',
          severity: 'high',
          message: 'Mutation missing authentication check',
          remediation: 'Add authentication: const identity = await ctx.auth.getUserIdentity();',
          context: 'export const myMutation = mutation({\n  handler: async (ctx) => {\n    // missing auth',
        },
      ],
      scannedFiles: ['/path/to/file.ts'],
      errors: [],
      metadata: {
        timestamp: '2025-01-01T00:00:00.000Z',
        filesScanned: 1,
        filesWithFindings: 1,
        rulesRun: ['auth/missing-auth-check'],
        scannerVersion: '0.1.0',
        durationMs: 100,
      },
    };

    const markdown = formatMarkdown(result);

    expect(markdown).toContain('`auth/missing-auth-check`');
    expect(markdown).toContain('Mutation missing authentication check');
    expect(markdown).toContain('**Location**: `/path/to/file.ts:42:12`');
    expect(markdown).toContain('**Category**: auth');
    expect(markdown).toContain('**Remediation**:');
    expect(markdown).toContain('Add authentication');
    expect(markdown).toContain('**Code Context**:');
    expect(markdown).toContain('```typescript');
  });

  it('should show success message when no findings', () => {
    const result: ScanResult = {
      findings: [],
      scannedFiles: ['/file1.ts', '/file2.ts'],
      errors: [],
      metadata: {
        timestamp: '2025-01-01T00:00:00.000Z',
        filesScanned: 2,
        filesWithFindings: 0,
        rulesRun: ['auth/missing-auth-check'],
        scannerVersion: '0.1.0',
        durationMs: 75,
      },
    };

    const markdown = formatMarkdown(result);

    expect(markdown).toContain('## Findings');
    expect(markdown).toContain('✅ No security issues found!');
  });

  it('should include errors section when present', () => {
    const result: ScanResult = {
      findings: [],
      scannedFiles: [],
      errors: [
        {
          file: '/error-file.ts',
          message: 'Parse error: unexpected token',
          stack: 'Error: Parse error\n  at parse (/scanner.ts:10)',
        },
        {
          file: '/another-error.ts',
          message: 'Type checking failed',
        },
      ],
      metadata: {
        timestamp: '2025-01-01T00:00:00.000Z',
        filesScanned: 0,
        filesWithFindings: 0,
        rulesRun: [],
        scannerVersion: '0.1.0',
        durationMs: 50,
      },
    };

    const markdown = formatMarkdown(result);

    expect(markdown).toContain('## Errors');
    expect(markdown).toContain('### /error-file.ts');
    expect(markdown).toContain('Parse error: unexpected token');
    expect(markdown).toContain('Error: Parse error');
    expect(markdown).toContain('### /another-error.ts');
    expect(markdown).toContain('Type checking failed');
  });

  it('should include scanner version in summary', () => {
    const result: ScanResult = {
      findings: [],
      scannedFiles: [],
      errors: [],
      metadata: {
        timestamp: '2025-01-01T00:00:00.000Z',
        filesScanned: 0,
        filesWithFindings: 0,
        rulesRun: [],
        scannerVersion: '0.1.0',
        durationMs: 50,
      },
    };

    const markdown = formatMarkdown(result);

    expect(markdown).toContain('**Scanner Version**: 0.1.0');
  });

  it('should include file-by-file breakdown section', () => {
    const result: ScanResult = {
      findings: [
        {
          file: '/path/to/file1.ts',
          line: 10,
          column: 5,
          endLine: 10,
          endColumn: 20,
          rule: 'auth/missing-auth-check',
          category: 'auth',
          severity: 'high',
          message: 'First issue in file1',
          remediation: 'Fix it',
          context: 'code',
        },
        {
          file: '/path/to/file1.ts',
          line: 20,
          column: 5,
          endLine: 20,
          endColumn: 20,
          rule: 'validation/weak',
          category: 'validation',
          severity: 'medium',
          message: 'Second issue in file1',
          remediation: 'Fix it',
          context: 'code',
        },
        {
          file: '/path/to/file2.ts',
          line: 15,
          column: 3,
          endLine: 15,
          endColumn: 10,
          rule: 'auth/missing-auth-check',
          category: 'auth',
          severity: 'high',
          message: 'Issue in file2',
          remediation: 'Fix it',
          context: 'code',
        },
      ],
      scannedFiles: ['/path/to/file1.ts', '/path/to/file2.ts'],
      errors: [],
      metadata: {
        timestamp: '2025-01-01T00:00:00.000Z',
        filesScanned: 2,
        filesWithFindings: 2,
        rulesRun: ['auth/missing-auth-check', 'validation/weak'],
        scannerVersion: '0.1.0',
        durationMs: 100,
      },
    };

    const markdown = formatMarkdown(result);

    expect(markdown).toContain('## Findings by File');
    expect(markdown).toContain('### /path/to/file1.ts (2)');
    expect(markdown).toContain('### /path/to/file2.ts (1)');
    expect(markdown).toContain('First issue in file1');
    expect(markdown).toContain('Second issue in file1');
    expect(markdown).toContain('Issue in file2');
  });

  it('should sort files alphabetically in file-by-file breakdown', () => {
    const result: ScanResult = {
      findings: [
        {
          file: '/z-file.ts',
          line: 1,
          column: 1,
          endLine: 1,
          endColumn: 1,
          rule: 'test',
          category: 'general',
          severity: 'high',
          message: 'Z file issue',
          remediation: 'Fix',
          context: 'code',
        },
        {
          file: '/a-file.ts',
          line: 1,
          column: 1,
          endLine: 1,
          endColumn: 1,
          rule: 'test',
          category: 'general',
          severity: 'high',
          message: 'A file issue',
          remediation: 'Fix',
          context: 'code',
        },
      ],
      scannedFiles: ['/z-file.ts', '/a-file.ts'],
      errors: [],
      metadata: {
        timestamp: '2025-01-01T00:00:00.000Z',
        filesScanned: 2,
        filesWithFindings: 2,
        rulesRun: ['test'],
        scannerVersion: '0.1.0',
        durationMs: 100,
      },
    };

    const markdown = formatMarkdown(result);

    const aFileIndex = markdown.indexOf('### /a-file.ts');
    const zFileIndex = markdown.indexOf('### /z-file.ts');

    // A file should appear before Z file
    expect(aFileIndex).toBeLessThan(zFileIndex);
  });

  it('should handle all severity levels', () => {
    const result: ScanResult = {
      findings: [
        {
          file: '/file.ts',
          line: 1,
          column: 1,
          endLine: 1,
          endColumn: 1,
          rule: 'test/critical',
          category: 'general',
          severity: 'critical',
          message: 'Critical',
          remediation: 'Fix',
          context: 'code',
        },
        {
          file: '/file.ts',
          line: 2,
          column: 1,
          endLine: 2,
          endColumn: 1,
          rule: 'test/high',
          category: 'general',
          severity: 'high',
          message: 'High',
          remediation: 'Fix',
          context: 'code',
        },
        {
          file: '/file.ts',
          line: 3,
          column: 1,
          endLine: 3,
          endColumn: 1,
          rule: 'test/medium',
          category: 'general',
          severity: 'medium',
          message: 'Medium',
          remediation: 'Fix',
          context: 'code',
        },
        {
          file: '/file.ts',
          line: 4,
          column: 1,
          endLine: 4,
          endColumn: 1,
          rule: 'test/low',
          category: 'general',
          severity: 'low',
          message: 'Low',
          remediation: 'Fix',
          context: 'code',
        },
        {
          file: '/file.ts',
          line: 5,
          column: 1,
          endLine: 5,
          endColumn: 1,
          rule: 'test/info',
          category: 'general',
          severity: 'info',
          message: 'Info',
          remediation: 'Fix',
          context: 'code',
        },
      ],
      scannedFiles: ['/file.ts'],
      errors: [],
      metadata: {
        timestamp: '2025-01-01T00:00:00.000Z',
        filesScanned: 1,
        filesWithFindings: 1,
        rulesRun: ['test/critical', 'test/high', 'test/medium', 'test/low', 'test/info'],
        scannerVersion: '0.1.0',
        durationMs: 100,
      },
    };

    const markdown = formatMarkdown(result);

    expect(markdown).toContain('### Critical (1)');
    expect(markdown).toContain('### High (1)');
    expect(markdown).toContain('### Medium (1)');
    expect(markdown).toContain('### Low (1)');
    expect(markdown).toContain('### Info (1)');
  });
});
