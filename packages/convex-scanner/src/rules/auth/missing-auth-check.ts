/**
 * Missing Auth Check Rule
 *
 * Detects mutations that don't check authentication via ctx.auth
 */

import type { Rule, RuleContext } from '../rule.js';
import type { Finding } from '../../types.js';
import { isMutation, isInternalFunction } from '../../parser/function-detector.js';
import { analyzeCtxUsage } from '../../parser/ctx-analyzer.js';
import { extractContext, getPosition } from '../../parser/context-extractor.js';

export const missingAuthCheckRule: Rule = {
  id: 'auth/missing-auth-check',
  name: 'Missing Authentication Check',
  category: 'auth',
  severity: 'high',
  description:
    'Mutations should verify user authentication before performing operations',

  check(context: RuleContext): Finding[] {
    const { function: func } = context;

    // Only check mutations (not queries or actions)
    if (!isMutation(func.type)) {
      return [];
    }

    // Skip internal mutations (they don't need auth checks)
    if (isInternalFunction(func.type)) {
      return [];
    }

    // Analyze ctx usage
    const ctxUsage = analyzeCtxUsage(func.node);

    // If the function uses ctx.auth, it's likely checking authentication
    if (ctxUsage.usesAuth) {
      return [];
    }

    // Generate finding for missing auth check
    const position = getPosition(func.sourceFile, func.node);
    const codeContext = extractContext(func.sourceFile, func.node);

    const finding: Finding = {
      file: func.filePath,
      line: position.line,
      column: position.column,
      endLine: position.endLine,
      endColumn: position.endColumn,
      rule: this.id,
      category: this.category,
      severity: this.severity,
      message: `Mutation '${func.name}' does not check user authentication`,
      remediation:
        "Add authentication check at the start of your mutation handler:\n\n" +
        "const identity = await ctx.auth.getUserIdentity();\n" +
        "if (!identity) {\n" +
        "  throw new Error('Unauthenticated');\n" +
        "}\n\n" +
        "Or use ctx.auth.getUserIdentity() to get the authenticated user.",
      context: codeContext,
    };

    return [finding];
  },
};
