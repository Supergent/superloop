/**
 * Tests for ConvexParser metadata extraction
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { ConvexParser } from '../convex-parser';
import { writeFileSync, mkdirSync, rmSync } from 'node:fs';
import { join } from 'node:path';

const TEMP_DIR = join(__dirname, '__temp__');

describe('ConvexParser metadata extraction', () => {
  beforeEach(() => {
    mkdirSync(TEMP_DIR, { recursive: true });
  });

  afterEach(() => {
    rmSync(TEMP_DIR, { recursive: true, force: true });
  });

  it('should extract args schema from mutation', () => {
    const testFile = join(TEMP_DIR, 'test.ts');
    writeFileSync(
      testFile,
      `
      import { mutation } from './_generated/server';
      import { v } from 'convex/values';

      export const createUser = mutation({
        args: {
          name: v.string(),
          age: v.number(),
        },
        handler: async (ctx, args) => {
          return { id: '123' };
        },
      });
      `
    );

    const parser = new ConvexParser([testFile]);
    const functions = parser.parseFile(testFile);

    expect(functions).toHaveLength(1);
    expect(functions[0]?.name).toBe('createUser');
    expect(functions[0]?.argsSchema).toContain('name');
    expect(functions[0]?.argsSchema).toContain('v.string()');
    expect(functions[0]?.argsSchema).toContain('age');
    expect(functions[0]?.argsSchema).toContain('v.number()');
  });

  it('should extract return type when specified', () => {
    const testFile = join(TEMP_DIR, 'test.ts');
    writeFileSync(
      testFile,
      `
      import { query } from './_generated/server';
      import { v } from 'convex/values';

      export const getUser = query({
        args: { id: v.string() },
        returns: v.object({ name: v.string(), age: v.number() }),
        handler: async (ctx, args) => {
          return { name: 'Alice', age: 30 };
        },
      });
      `
    );

    const parser = new ConvexParser([testFile]);
    const functions = parser.parseFile(testFile);

    expect(functions).toHaveLength(1);
    expect(functions[0]?.name).toBe('getUser');
    expect(functions[0]?.returnType).toContain('v.object');
  });

  it('should handle functions without args', () => {
    const testFile = join(TEMP_DIR, 'test.ts');
    writeFileSync(
      testFile,
      `
      import { query } from './_generated/server';

      export const listAll = query({
        handler: async (ctx) => {
          return [];
        },
      });
      `
    );

    const parser = new ConvexParser([testFile]);
    const functions = parser.parseFile(testFile);

    expect(functions).toHaveLength(1);
    expect(functions[0]?.name).toBe('listAll');
    expect(functions[0]?.argsSchema).toBeUndefined();
  });

  it('should extract metadata from internal functions', () => {
    const testFile = join(TEMP_DIR, 'test.ts');
    writeFileSync(
      testFile,
      `
      import { internalMutation } from './_generated/server';
      import { v } from 'convex/values';

      export const updateInternal = internalMutation({
        args: { id: v.string() },
        handler: async (ctx, args) => {
          return null;
        },
      });
      `
    );

    const parser = new ConvexParser([testFile]);
    const functions = parser.parseFile(testFile);

    expect(functions).toHaveLength(1);
    expect(functions[0]?.name).toBe('updateInternal');
    expect(functions[0]?.type).toBe('internalMutation');
    expect(functions[0]?.argsSchema).toContain('id');
    expect(functions[0]?.argsSchema).toContain('v.string()');
  });

  it('should extract complex nested args schema', () => {
    const testFile = join(TEMP_DIR, 'test.ts');
    writeFileSync(
      testFile,
      `
      import { mutation } from './_generated/server';
      import { v } from 'convex/values';

      export const createPost = mutation({
        args: {
          title: v.string(),
          content: v.string(),
          metadata: v.object({
            tags: v.array(v.string()),
            publishedAt: v.optional(v.number()),
          }),
        },
        handler: async (ctx, args) => {
          return { id: '123' };
        },
      });
      `
    );

    const parser = new ConvexParser([testFile]);
    const functions = parser.parseFile(testFile);

    expect(functions).toHaveLength(1);
    expect(functions[0]?.name).toBe('createPost');
    expect(functions[0]?.argsSchema).toContain('title');
    expect(functions[0]?.argsSchema).toContain('metadata');
    expect(functions[0]?.argsSchema).toContain('v.object');
    expect(functions[0]?.argsSchema).toContain('tags');
    expect(functions[0]?.argsSchema).toContain('v.array');
  });

  it('should parse all variable declarations in a single statement', () => {
    const testFile = join(TEMP_DIR, 'multiple-decls.ts');
    writeFileSync(
      testFile,
      `
      import { query, mutation } from './_generated/server';
      import { v } from 'convex/values';

      // Multiple declarations in a single const statement
      export const getUser = query({
        args: { id: v.string() },
        handler: async (ctx, args) => {
          return { name: 'Alice' };
        },
      }), updateUser = mutation({
        args: { id: v.string(), name: v.string() },
        handler: async (ctx, args) => {
          return { id: args.id };
        },
      });
      `
    );

    const parser = new ConvexParser([testFile]);
    const functions = parser.parseFile(testFile);

    // Should detect both functions even though they're in one statement
    expect(functions).toHaveLength(2);

    const getUser = functions.find(f => f.name === 'getUser');
    const updateUser = functions.find(f => f.name === 'updateUser');

    expect(getUser).toBeDefined();
    expect(getUser?.type).toBe('query');
    expect(getUser?.argsSchema).toContain('id: v.string()');

    expect(updateUser).toBeDefined();
    expect(updateUser?.type).toBe('mutation');
    expect(updateUser?.argsSchema).toContain('id: v.string()');
    expect(updateUser?.argsSchema).toContain('name: v.string()');
  });
});
