import { describe, it, expect } from 'vitest';
import { resolve } from 'node:path';
import { ConvexParser } from '../../../parser/convex-parser.js';
import { missingAuthCheckRule } from '../missing-auth-check.js';
import type { RuleContext } from '../../rule.js';

describe('missing-auth-check', () => {
  const fixturesPath = resolve(__dirname, '../../../__tests__/fixtures/convex');

  it('should flag mutation without auth check', () => {
    const filePath = resolve(fixturesPath, 'mutation-no-auth.ts');
    const parser = new ConvexParser([filePath]);
    const functions = parser.parseFile(filePath);

    expect(functions.length).toBeGreaterThan(0);

    const func = functions[0];
    expect(func).toBeDefined();

    const context: RuleContext = {
      function: func!,
      typeChecker: parser.getTypeChecker(),
      program: parser.getProgram(),
    };

    const findings = missingAuthCheckRule.check(context);
    expect(findings.length).toBe(1);
    expect(findings[0]?.rule).toBe('auth/missing-auth-check');
    expect(findings[0]?.severity).toBe('high');
  });

  it('should not flag mutation with auth check', () => {
    const filePath = resolve(fixturesPath, 'mutation-with-auth.ts');
    const parser = new ConvexParser([filePath]);
    const functions = parser.parseFile(filePath);

    expect(functions.length).toBeGreaterThan(0);

    const func = functions[0];
    expect(func).toBeDefined();

    const context: RuleContext = {
      function: func!,
      typeChecker: parser.getTypeChecker(),
      program: parser.getProgram(),
    };

    const findings = missingAuthCheckRule.check(context);
    expect(findings.length).toBe(0);
  });

  it('should not flag internal mutation', () => {
    const filePath = resolve(fixturesPath, 'internal-mutation.ts');
    const parser = new ConvexParser([filePath]);
    const functions = parser.parseFile(filePath);

    expect(functions.length).toBeGreaterThan(0);

    const func = functions[0];
    expect(func).toBeDefined();

    const context: RuleContext = {
      function: func!,
      typeChecker: parser.getTypeChecker(),
      program: parser.getProgram(),
    };

    const findings = missingAuthCheckRule.check(context);
    expect(findings.length).toBe(0);
  });

  it('should not flag query (only mutations)', () => {
    const filePath = resolve(fixturesPath, 'query-with-auth.ts');
    const parser = new ConvexParser([filePath]);
    const functions = parser.parseFile(filePath);

    expect(functions.length).toBeGreaterThan(0);

    const func = functions[0];
    expect(func).toBeDefined();

    const context: RuleContext = {
      function: func!,
      typeChecker: parser.getTypeChecker(),
      program: parser.getProgram(),
    };

    const findings = missingAuthCheckRule.check(context);
    expect(findings.length).toBe(0);
  });
});
