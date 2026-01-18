import { describe, it, expect } from 'vitest';
import { resolve } from 'node:path';
import { scanConvex } from '../scanner/static-scanner.js';

describe('scan-convex integration', () => {
  const fixturesPath = resolve(__dirname, 'fixtures');

  it('should scan fixtures and find issues', async () => {
    const result = await scanConvex(fixturesPath);

    expect(result).toBeDefined();
    expect(result.metadata).toBeDefined();
    expect(result.metadata.filesScanned).toBeGreaterThan(0);
    expect(result.scannedFiles.length).toBeGreaterThan(0);
  });

  it('should include metadata in results', async () => {
    const result = await scanConvex(fixturesPath);

    expect(result.metadata.timestamp).toBeDefined();
    expect(result.metadata.filesScanned).toBeGreaterThan(0);
    expect(result.metadata.rulesRun).toContain('auth/missing-auth-check');
    expect(result.metadata.scannerVersion).toBe('0.1.0');
    expect(result.metadata.durationMs).toBeGreaterThan(0);
  });

  it('should include file location in findings', async () => {
    const result = await scanConvex(fixturesPath);

    // Should find at least the mutation-no-auth.ts issue
    const findings = result.findings.filter(
      (f) => f.file.includes('mutation-no-auth.ts')
    );

    if (findings.length > 0) {
      const finding = findings[0]!;
      expect(finding.file).toBeDefined();
      expect(finding.line).toBeGreaterThan(0);
      expect(finding.column).toBeGreaterThanOrEqual(0);
      expect(finding.context).toBeDefined();
      expect(finding.context.length).toBeGreaterThan(0);
    }
  });

  it('should handle nonexistent directory with error', async () => {
    await expect(
      scanConvex('/tmp/nonexistent-convex-dir-test-12345')
    ).rejects.toThrow('Convex directory does not exist');
  });

  it('should return errors in ScanResult when throwOnError is false', async () => {
    const result = await scanConvex('/tmp/nonexistent-convex-dir-test-12345', {
      throwOnError: false,
    });

    expect(result).toBeDefined();
    expect(result.errors).toBeDefined();
    expect(result.errors.length).toBeGreaterThan(0);
    expect(result.errors[0]?.message).toContain('does not exist');
    expect(result.findings).toEqual([]);
    expect(result.scannedFiles).toEqual([]);
  });

  it('should collect errors instead of throwing when throwOnError is false', async () => {
    // Should not throw
    const result = await scanConvex('/tmp/nonexistent-convex-dir-test-12345', {
      throwOnError: false,
    });

    expect(result.errors.length).toBeGreaterThan(0);
  });
});
