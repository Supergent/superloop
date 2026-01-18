import { describe, it, expect } from 'vitest';
import { resolve } from 'node:path';
import { ConvexParser } from '../../../parser/convex-parser.js';
import { missingAuthCheckRule } from '../missing-auth-check.js';
import type { RuleContext, RuleConfiguration } from '../../rule.js';

describe('missing-auth-check', () => {
  const fixturesPath = resolve(__dirname, '../../../__tests__/fixtures/convex');

  const getFindings = (
    fileName: string,
    options?: Record<string, unknown>
  ) => {
    const filePath = resolve(fixturesPath, fileName);
    const parser = new ConvexParser([filePath]);
    const functions = parser.parseFile(filePath);

    expect(functions.length).toBeGreaterThan(0);

    const func = functions[0];
    expect(func).toBeDefined();

    const config: RuleConfiguration | undefined = options
      ? {
          enabled: true,
          severity: 'high',
          options,
        }
      : undefined;

    const context: RuleContext = {
      function: func!,
      typeChecker: parser.getTypeChecker(),
      program: parser.getProgram(),
      config,
    };

    return missingAuthCheckRule.check(context);
  };

  it('should flag mutation without auth check', () => {
    const findings = getFindings('mutation-no-auth.ts');
    expect(findings.length).toBe(1);
    expect(findings[0]?.rule).toBe('auth/missing-auth-check');
    expect(findings[0]?.severity).toBe('high');
  });

  it('should not flag mutation with auth check', () => {
    const findings = getFindings('mutation-with-auth.ts');
    expect(findings.length).toBe(0);
  });

  it('should not flag internal mutation', () => {
    const findings = getFindings('internal-mutation.ts');
    expect(findings.length).toBe(0);
  });

  it('should flag query without auth check', () => {
    const findings = getFindings('query-no-auth.ts');
    expect(findings.length).toBe(1);
  });

  it('should not flag query with auth check', () => {
    const findings = getFindings('query-with-auth.ts');
    expect(findings.length).toBe(0);
  });

  it('should flag action without auth check', () => {
    const findings = getFindings('action-no-auth.ts');
    expect(findings.length).toBe(1);
  });

  it('should not flag action with auth check', () => {
    const findings = getFindings('action-with-auth.ts');
    expect(findings.length).toBe(0);
  });

  it('should flag httpAction without auth check', () => {
    const findings = getFindings('http-action-no-auth.ts');
    expect(findings.length).toBe(1);
  });

  it('should respect inline suppression comment', () => {
    const findings = getFindings('mutation-with-suppression.ts');
    expect(findings.length).toBe(0);
  });

  it('should respect allowList patterns', () => {
    const findings = getFindings('mutation-no-auth.ts', {
      allowList: ['create*'],
    });
    expect(findings.length).toBe(0);
  });

  it('should match allowList patterns case-insensitively', () => {
    const findings = getFindings('action-no-auth.ts', {
      allowList: ['SEND*'],
    });
    expect(findings.length).toBe(0);
  });

  it('should skip queries when checkQueries is disabled', () => {
    const findings = getFindings('query-no-auth.ts', {
      checkQueries: false,
    });
    expect(findings.length).toBe(0);
  });

  it('should skip actions when checkActions is disabled', () => {
    const findings = getFindings('action-no-auth.ts', {
      checkActions: false,
    });
    expect(findings.length).toBe(0);
  });

  it('should ignore inline suppression when allowInlineSuppressions is false', () => {
    const findings = getFindings('mutation-with-suppression.ts', {
      allowInlineSuppressions: false,
    });
    expect(findings.length).toBe(1);
  });
});
