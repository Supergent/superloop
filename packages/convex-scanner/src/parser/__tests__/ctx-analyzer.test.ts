import { describe, it, expect } from 'vitest';
import ts from 'typescript';
import { analyzeCtxUsage, hasAuthCheck } from '../ctx-analyzer.js';

describe('ctx-analyzer', () => {
  describe('analyzeCtxUsage', () => {
    it('should detect ctx.auth usage', () => {
      const code = `
        async function handler(ctx) {
          const identity = await ctx.auth.getUserIdentity();
          return identity;
        }
      `;

      const sourceFile = ts.createSourceFile(
        'test.ts',
        code,
        ts.ScriptTarget.ES2022,
        true
      );

      const usage = analyzeCtxUsage(sourceFile);
      expect(usage.usesAuth).toBe(true);
      expect(usage.authUsageNodes.length).toBeGreaterThan(0);
    });

    it('should detect ctx.db usage', () => {
      const code = `
        async function handler(ctx) {
          const items = await ctx.db.query('items').collect();
          return items;
        }
      `;

      const sourceFile = ts.createSourceFile(
        'test.ts',
        code,
        ts.ScriptTarget.ES2022,
        true
      );

      const usage = analyzeCtxUsage(sourceFile);
      expect(usage.usesDb).toBe(true);
    });

    it('should detect no ctx usage', () => {
      const code = `
        async function handler(ctx) {
          return { message: 'hello' };
        }
      `;

      const sourceFile = ts.createSourceFile(
        'test.ts',
        code,
        ts.ScriptTarget.ES2022,
        true
      );

      const usage = analyzeCtxUsage(sourceFile);
      expect(usage.usesAuth).toBe(false);
      expect(usage.usesDb).toBe(false);
      expect(usage.usesStorage).toBe(false);
      expect(usage.usesScheduler).toBe(false);
    });
  });

  describe('hasAuthCheck', () => {
    it('should return true when auth is checked', () => {
      const code = `
        async function handler(ctx) {
          await ctx.auth.getUserIdentity();
        }
      `;

      const sourceFile = ts.createSourceFile(
        'test.ts',
        code,
        ts.ScriptTarget.ES2022,
        true
      );

      expect(hasAuthCheck(sourceFile)).toBe(true);
    });

    it('should return false when auth is not checked', () => {
      const code = `
        async function handler(ctx) {
          await ctx.db.insert('items', {});
        }
      `;

      const sourceFile = ts.createSourceFile(
        'test.ts',
        code,
        ts.ScriptTarget.ES2022,
        true
      );

      expect(hasAuthCheck(sourceFile)).toBe(false);
    });
  });
});
