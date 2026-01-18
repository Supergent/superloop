import { describe, it, expect } from 'vitest';
import ts from 'typescript';
import { detectFunctionType, isInternalFunction, isMutation, isQuery } from '../function-detector.js';

describe('function-detector', () => {
  describe('detectFunctionType', () => {
    it('should detect query function', () => {
      const code = 'query({ handler: async (ctx) => {} })';
      const sourceFile = ts.createSourceFile(
        'test.ts',
        code,
        ts.ScriptTarget.ES2022,
        true
      );

      let result: any = null;
      ts.forEachChild(sourceFile, (node) => {
        if (ts.isExpressionStatement(node) && ts.isCallExpression(node.expression)) {
          result = detectFunctionType(node.expression);
        }
      });

      expect(result).toBe('query');
    });

    it('should detect mutation function', () => {
      const code = 'mutation({ handler: async (ctx) => {} })';
      const sourceFile = ts.createSourceFile(
        'test.ts',
        code,
        ts.ScriptTarget.ES2022,
        true
      );

      let result: any = null;
      ts.forEachChild(sourceFile, (node) => {
        if (ts.isExpressionStatement(node) && ts.isCallExpression(node.expression)) {
          result = detectFunctionType(node.expression);
        }
      });

      expect(result).toBe('mutation');
    });

    it('should detect internalMutation function', () => {
      const code = 'internalMutation({ handler: async (ctx) => {} })';
      const sourceFile = ts.createSourceFile(
        'test.ts',
        code,
        ts.ScriptTarget.ES2022,
        true
      );

      let result: any = null;
      ts.forEachChild(sourceFile, (node) => {
        if (ts.isExpressionStatement(node) && ts.isCallExpression(node.expression)) {
          result = detectFunctionType(node.expression);
        }
      });

      expect(result).toBe('internalMutation');
    });
  });

  describe('isInternalFunction', () => {
    it('should return true for internal functions', () => {
      expect(isInternalFunction('internalMutation')).toBe(true);
      expect(isInternalFunction('internalQuery')).toBe(true);
      expect(isInternalFunction('internalAction')).toBe(true);
    });

    it('should return false for public functions', () => {
      expect(isInternalFunction('mutation')).toBe(false);
      expect(isInternalFunction('query')).toBe(false);
      expect(isInternalFunction('action')).toBe(false);
    });
  });

  describe('isMutation', () => {
    it('should return true for mutation types', () => {
      expect(isMutation('mutation')).toBe(true);
      expect(isMutation('internalMutation')).toBe(true);
    });

    it('should return false for non-mutation types', () => {
      expect(isMutation('query')).toBe(false);
      expect(isMutation('action')).toBe(false);
    });
  });

  describe('isQuery', () => {
    it('should return true for query types', () => {
      expect(isQuery('query')).toBe(true);
      expect(isQuery('internalQuery')).toBe(true);
    });

    it('should return false for non-query types', () => {
      expect(isQuery('mutation')).toBe(false);
      expect(isQuery('action')).toBe(false);
    });
  });
});
