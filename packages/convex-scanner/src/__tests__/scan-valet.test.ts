import { describe, it, expect } from 'vitest';
import { resolve } from 'node:path';
import { existsSync } from 'node:fs';
import { scanConvex } from '../scanner/static-scanner.js';

describe('scan-valet real-world test', () => {
  const valetConvexPath = resolve(__dirname, '../../../valet/convex');

  // Skip if valet package doesn't exist (e.g., in isolated test env)
  const shouldRun = existsSync(valetConvexPath);

  it.skipIf(!shouldRun)('should scan valet/convex without errors', async () => {
    const result = await scanConvex(resolve(__dirname, '../../../valet'), {
      convexDir: './convex',
    });

    expect(result).toBeDefined();
    expect(result.metadata).toBeDefined();
    expect(result.scannedFiles.length).toBeGreaterThan(0);
    expect(result.errors).toBeDefined();

    // Log summary for manual inspection
    console.log('\n=== Valet Convex Scan Summary ===');
    console.log(`Files scanned: ${result.metadata.filesScanned}`);
    console.log(`Files with findings: ${result.metadata.filesWithFindings}`);
    console.log(`Total findings: ${result.findings.length}`);
    console.log(`Errors: ${result.errors.length}`);
    console.log(`Duration: ${result.metadata.durationMs}ms`);

    if (result.findings.length > 0) {
      console.log('\nFindings by severity:');
      const bySeverity = result.findings.reduce(
        (acc, f) => {
          acc[f.severity] = (acc[f.severity] || 0) + 1;
          return acc;
        },
        {} as Record<string, number>
      );
      for (const [severity, count] of Object.entries(bySeverity)) {
        console.log(`  ${severity}: ${count}`);
      }
    }

    if (result.errors.length > 0) {
      console.log('\nErrors encountered:');
      for (const error of result.errors) {
        console.log(`  ${error.file}: ${error.message}`);
      }
    }
  });

  it.skipIf(!shouldRun)(
    'should complete scan within performance target',
    async () => {
      const startTime = Date.now();
      const result = await scanConvex(resolve(__dirname, '../../../valet'), {
        convexDir: './convex',
      });
      const duration = Date.now() - startTime;

      // Should complete within 10 seconds (performance constraint from spec)
      expect(duration).toBeLessThan(10000);
      expect(result.metadata.durationMs).toBeLessThan(10000);
    }
  );

  it.skipIf(!shouldRun)('should detect known Convex function patterns', async () => {
    const result = await scanConvex(resolve(__dirname, '../../../valet'), {
      convexDir: './convex',
    });

    // Valet has auth.ts and subscriptions.ts which should contain Convex functions
    const scannedFileNames = result.scannedFiles.map((f) => f.split('/').pop());

    expect(scannedFileNames).toContain('auth.ts');
    expect(scannedFileNames).toContain('subscriptions.ts');
    expect(scannedFileNames).toContain('schema.ts');
  });

  it.skipIf(!shouldRun)(
    'should provide detailed metadata in scan results',
    async () => {
      const result = await scanConvex(resolve(__dirname, '../../../valet'), {
        convexDir: './convex',
      });

      expect(result.metadata.timestamp).toBeDefined();
      expect(result.metadata.filesScanned).toBeGreaterThan(0);
      expect(result.metadata.rulesRun).toContain('auth/missing-auth-check');
      expect(result.metadata.scannerVersion).toBe('0.1.0');
      expect(result.metadata.durationMs).toBeGreaterThan(0);
    }
  );

  it.skipIf(!shouldRun)(
    'should include file location details in any findings',
    async () => {
      const result = await scanConvex(resolve(__dirname, '../../../valet'), {
        convexDir: './convex',
      });

      // If there are findings, they should have proper location data
      for (const finding of result.findings) {
        expect(finding.file).toBeDefined();
        expect(finding.line).toBeGreaterThan(0);
        expect(finding.column).toBeGreaterThanOrEqual(0);
        expect(finding.rule).toBeDefined();
        expect(finding.category).toBeDefined();
        expect(finding.severity).toBeDefined();
        expect(finding.message).toBeDefined();
        expect(finding.remediation).toBeDefined();
        expect(finding.context).toBeDefined();
      }
    }
  );
});
