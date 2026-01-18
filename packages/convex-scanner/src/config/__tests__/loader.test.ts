import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { loadConfig } from '../loader.js';
import { DEFAULT_IGNORE_PATTERNS } from '../defaults.js';
import { writeFileSync, mkdirSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

describe('config-loader', () => {
  let tempDir: string;

  beforeEach(() => {
    tempDir = join(tmpdir(), `convex-scanner-test-${Date.now()}`);
    mkdirSync(tempDir, { recursive: true });
  });

  afterEach(() => {
    rmSync(tempDir, { recursive: true, force: true });
  });

  it('should load default config when no config file exists', async () => {
    const config = await loadConfig(tempDir);

    expect(config.convexDir).toBe('./convex');
    expect(config.ignore).toEqual(DEFAULT_IGNORE_PATTERNS);
    expect(config.rules['auth/missing-auth-check']).toBeDefined();
    expect(config.rules['auth/missing-auth-check']?.enabled).toBe(true);
    expect(
      config.rules['auth/missing-auth-check']?.options?.checkQueries
    ).toBe(true);
  });

  it('should have default ignore patterns', async () => {
    const config = await loadConfig(tempDir);

    expect(config.ignore).toContain('**/node_modules/**');
    expect(config.ignore).toContain('**/.git/**');
    expect(config.ignore).toContain('**/dist/**');
    expect(config.ignore).toContain('**/build/**');
    expect(config.ignore).toContain('**/_generated/**');
  });

  it('should override defaults with custom ignore patterns', async () => {
    // Create custom config with custom ignore patterns
    const configContent = `
      export default {
        ignore: ['**/custom/**', '**/test/**'],
      };
    `;
    writeFileSync(join(tempDir, 'convex-scanner.config.js'), configContent);

    const config = await loadConfig(tempDir);

    // Custom ignore should replace defaults, not merge
    expect(config.ignore).toEqual(['**/custom/**', '**/test/**']);
    expect(config.ignore).not.toContain('**/node_modules/**');
  });

  it('should allow including _generated when custom ignore is set', async () => {
    // Create custom config that explicitly excludes _generated from ignore
    const configContent = `
      export default {
        ignore: ['**/node_modules/**', '**/.git/**'],
      };
    `;
    writeFileSync(join(tempDir, 'convex-scanner.config.js'), configContent);

    const config = await loadConfig(tempDir);

    expect(config.ignore).not.toContain('**/_generated/**');
    expect(config.ignore).toContain('**/node_modules/**');
    expect(config.ignore).toContain('**/.git/**');
  });
});
