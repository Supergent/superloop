import { describe, it, expect } from 'vitest';
import { formatJson } from '../json.js';
import type { ScanResult } from '../../types.js';

describe('json formatter', () => {
  it('should format scan result as valid JSON', () => {
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

    const json = formatJson(result);

    expect(json).toBeDefined();
    expect(() => JSON.parse(json)).not.toThrow();

    const parsed = JSON.parse(json) as ScanResult;
    expect(parsed.findings).toHaveLength(1);
    expect(parsed.metadata.filesScanned).toBe(1);
  });

  it('should format empty result as valid JSON', () => {
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

    const json = formatJson(result);

    expect(json).toBeDefined();
    expect(() => JSON.parse(json)).not.toThrow();

    const parsed = JSON.parse(json) as ScanResult;
    expect(parsed.findings).toHaveLength(0);
    expect(parsed.scannedFiles).toHaveLength(0);
  });

  it('should include all ScanResult fields', () => {
    const result: ScanResult = {
      findings: [],
      scannedFiles: ['/file1.ts', '/file2.ts'],
      errors: [
        {
          file: '/error.ts',
          message: 'Parse error',
          stack: 'Error stack trace',
        },
      ],
      metadata: {
        timestamp: '2025-01-01T00:00:00.000Z',
        filesScanned: 2,
        filesWithFindings: 0,
        rulesRun: ['auth/missing-auth-check'],
        scannerVersion: '0.1.0',
        durationMs: 75,
      },
    };

    const json = formatJson(result);
    const parsed = JSON.parse(json) as ScanResult;

    expect(parsed.findings).toBeDefined();
    expect(parsed.scannedFiles).toHaveLength(2);
    expect(parsed.errors).toHaveLength(1);
    expect(parsed.metadata).toBeDefined();
    expect(parsed.errors[0]?.message).toBe('Parse error');
  });

  it('should produce pretty-printed JSON', () => {
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
        durationMs: 10,
      },
    };

    const json = formatJson(result);

    // Should be formatted with indentation
    expect(json).toContain('\n');
    expect(json).toContain('  ');
  });

  it('should include all metadata fields in output', () => {
    const result: ScanResult = {
      findings: [],
      scannedFiles: [],
      errors: [],
      metadata: {
        timestamp: '2025-01-17T12:34:56.789Z',
        filesScanned: 42,
        filesWithFindings: 7,
        rulesRun: ['auth/missing-auth-check', 'validation/weak-validator'],
        scannerVersion: '0.1.0',
        durationMs: 1234,
      },
    };

    const json = formatJson(result);
    const parsed = JSON.parse(json) as ScanResult;

    expect(parsed.metadata.timestamp).toBe('2025-01-17T12:34:56.789Z');
    expect(parsed.metadata.filesScanned).toBe(42);
    expect(parsed.metadata.filesWithFindings).toBe(7);
    expect(parsed.metadata.rulesRun).toEqual(['auth/missing-auth-check', 'validation/weak-validator']);
    expect(parsed.metadata.scannerVersion).toBe('0.1.0');
    expect(parsed.metadata.durationMs).toBe(1234);
  });

  it('should preserve all finding fields in output', () => {
    const result: ScanResult = {
      findings: [
        {
          file: '/test/path/file.ts',
          line: 42,
          column: 15,
          endLine: 45,
          endColumn: 20,
          rule: 'auth/missing-auth-check',
          category: 'auth',
          severity: 'high',
          message: 'Detailed message about the issue',
          remediation: 'Detailed remediation steps',
          context: 'Multi-line\ncode\ncontext',
        },
      ],
      scannedFiles: [],
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

    const json = formatJson(result);
    const parsed = JSON.parse(json) as ScanResult;

    const finding = parsed.findings[0]!;
    expect(finding.file).toBe('/test/path/file.ts');
    expect(finding.line).toBe(42);
    expect(finding.column).toBe(15);
    expect(finding.endLine).toBe(45);
    expect(finding.endColumn).toBe(20);
    expect(finding.rule).toBe('auth/missing-auth-check');
    expect(finding.category).toBe('auth');
    expect(finding.severity).toBe('high');
    expect(finding.message).toBe('Detailed message about the issue');
    expect(finding.remediation).toBe('Detailed remediation steps');
    expect(finding.context).toBe('Multi-line\ncode\ncontext');
  });

  it('should preserve all error fields in output', () => {
    const result: ScanResult = {
      findings: [],
      scannedFiles: [],
      errors: [
        {
          file: '/error/file.ts',
          message: 'Detailed error message',
          stack: 'Error: Stack trace\n  at function (/file.ts:10:5)',
        },
        {
          file: '/another/error.ts',
          message: 'Another error without stack',
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

    const json = formatJson(result);
    const parsed = JSON.parse(json) as ScanResult;

    expect(parsed.errors).toHaveLength(2);
    expect(parsed.errors[0]?.file).toBe('/error/file.ts');
    expect(parsed.errors[0]?.message).toBe('Detailed error message');
    expect(parsed.errors[0]?.stack).toBe('Error: Stack trace\n  at function (/file.ts:10:5)');
    expect(parsed.errors[1]?.file).toBe('/another/error.ts');
    expect(parsed.errors[1]?.message).toBe('Another error without stack');
    expect(parsed.errors[1]?.stack).toBeUndefined();
  });

  it('should preserve scannedFiles array in output', () => {
    const result: ScanResult = {
      findings: [],
      scannedFiles: [
        '/path/to/file1.ts',
        '/path/to/file2.tsx',
        '/path/to/nested/file3.ts',
      ],
      errors: [],
      metadata: {
        timestamp: '2025-01-01T00:00:00.000Z',
        filesScanned: 3,
        filesWithFindings: 0,
        rulesRun: ['auth/missing-auth-check'],
        scannerVersion: '0.1.0',
        durationMs: 100,
      },
    };

    const json = formatJson(result);
    const parsed = JSON.parse(json) as ScanResult;

    expect(parsed.scannedFiles).toHaveLength(3);
    expect(parsed.scannedFiles).toEqual([
      '/path/to/file1.ts',
      '/path/to/file2.tsx',
      '/path/to/nested/file3.ts',
    ]);
  });
});
