import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { resolve, join } from 'node:path';
import { mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { discoverFiles, normalizeConvexDirs } from '../file-discovery.js';

describe('file-discovery', () => {
  const testRoot = resolve(__dirname, '__test-fixtures__');
  const convexDir = join(testRoot, 'convex');
  const generatedDir = join(convexDir, '_generated');

  beforeAll(() => {
    // Create test directory structure
    mkdirSync(convexDir, { recursive: true });
    mkdirSync(generatedDir, { recursive: true });
    mkdirSync(join(testRoot, 'node_modules'), { recursive: true });

    // Create test files
    writeFileSync(join(convexDir, 'queries.ts'), 'export const test = query({});');
    writeFileSync(join(convexDir, 'mutations.tsx'), 'export const test = mutation({});');
    writeFileSync(join(generatedDir, 'api.ts'), '// generated');
    writeFileSync(join(testRoot, 'node_modules', 'lib.ts'), '// node_modules');
  });

  afterAll(() => {
    // Clean up test directory
    rmSync(testRoot, { recursive: true, force: true });
  });

  describe('discoverFiles', () => {
    it('should discover .ts and .tsx files', async () => {
      const files = await discoverFiles(convexDir, []);

      expect(files.length).toBeGreaterThanOrEqual(2);
      expect(files.some((f) => f.endsWith('queries.ts'))).toBe(true);
      expect(files.some((f) => f.endsWith('mutations.tsx'))).toBe(true);
    });

    it('should skip files matching ignore patterns', async () => {
      const files = await discoverFiles(convexDir, ['**/_generated/**']);

      expect(files.some((f) => f.includes('_generated'))).toBe(false);
      expect(files.some((f) => f.endsWith('queries.ts'))).toBe(true);
    });

    it('should respect node_modules ignore pattern', async () => {
      const files = await discoverFiles(testRoot, ['**/node_modules/**']);

      expect(files.some((f) => f.includes('node_modules'))).toBe(false);
    });

    it('should include _generated when not in ignore patterns', async () => {
      const files = await discoverFiles(convexDir, []);

      expect(files.some((f) => f.includes('_generated'))).toBe(true);
      expect(files.some((f) => f.endsWith('api.ts'))).toBe(true);
    });

    it('should throw error for nonexistent directory', async () => {
      await expect(
        discoverFiles('/nonexistent/path/12345', [])
      ).rejects.toThrow('Convex directory does not exist');
    });

    it('should handle multiple directories', async () => {
      const dir2 = join(testRoot, 'convex2');
      mkdirSync(dir2, { recursive: true });
      writeFileSync(join(dir2, 'actions.ts'), 'export const test = action({});');

      const files = await discoverFiles([convexDir, dir2], ['**/_generated/**']);

      expect(files.some((f) => f.endsWith('queries.ts'))).toBe(true);
      expect(files.some((f) => f.endsWith('actions.ts'))).toBe(true);

      rmSync(dir2, { recursive: true, force: true });
    });
  });

  describe('normalizeConvexDirs', () => {
    it('should resolve relative paths from project root', () => {
      const projectPath = '/project/root';
      const dirs = normalizeConvexDirs(projectPath, './convex');

      expect(dirs).toEqual([resolve(projectPath, './convex')]);
    });

    it('should handle array of directories', () => {
      const projectPath = '/project/root';
      const dirs = normalizeConvexDirs(projectPath, ['./convex', './packages/app/convex']);

      expect(dirs.length).toBe(2);
      expect(dirs[0]).toBe(resolve(projectPath, './convex'));
      expect(dirs[1]).toBe(resolve(projectPath, './packages/app/convex'));
    });

    it('should handle absolute paths', () => {
      const projectPath = '/project/root';
      const absolutePath = '/absolute/convex';
      const dirs = normalizeConvexDirs(projectPath, absolutePath);

      expect(dirs).toEqual([absolutePath]);
    });

    it('should auto-append convex when pointing to project root', () => {
      // When project root has a convex subdirectory
      const dirs = normalizeConvexDirs(testRoot, './convex');

      // Should resolve to testRoot/convex
      expect(dirs[0]).toBe(convexDir);
    });

    it('should not double-append convex when path already points to convex dir', () => {
      // When path already ends with convex
      const dirs = normalizeConvexDirs(testRoot, convexDir);

      // Should not become testRoot/convex/convex
      expect(dirs[0]).toBe(convexDir);
      expect(dirs[0]).not.toContain('convex/convex');
    });

    it('should handle project root as input by finding convex subdirectory', () => {
      // Simulate passing the project root, expecting it to find ./convex
      const dirs = normalizeConvexDirs(testRoot, '.');

      // Should find and use testRoot/convex
      expect(dirs[0]).toBe(convexDir);
    });

    it('should not create convex/convex when projectPath points to convex dir', () => {
      // When projectPath already points to a convex directory (e.g., ./packages/valet/convex)
      // and convexDirs is the default 'convex', should use projectPath directly
      const dirs = normalizeConvexDirs(convexDir, 'convex');

      // Should resolve to convexDir, not convexDir/convex
      expect(dirs[0]).toBe(convexDir);
      expect(dirs[0]).not.toContain('convex/convex');
    });

    it('should handle ./convex when projectPath already points to convex dir', () => {
      // Regression test: when projectPath is already a convex directory
      // and convexDirs is './convex', should use projectPath directly
      const dirs = normalizeConvexDirs(convexDir, './convex');

      // Should resolve to convexDir, not convexDir/convex
      expect(dirs[0]).toBe(convexDir);
      expect(dirs[0]).not.toContain('convex/convex');
    });
  });
});
