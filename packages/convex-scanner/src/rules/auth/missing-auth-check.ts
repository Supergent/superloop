/**
 * Missing Auth Check Rule
 *
 * Detects Convex functions that don't check authentication via ctx.auth
 */

import type { Rule, RuleContext } from '../rule.js';
import type { Finding } from '../../types.js';
import type { ConvexFunctionType } from '../../parser/convex-parser.js';
import {
  isMutation,
  isInternalFunction,
  isQuery,
  isAction,
} from '../../parser/function-detector.js';
import { analyzeCtxUsage } from '../../parser/ctx-analyzer.js';
import { extractContext, getPosition } from '../../parser/context-extractor.js';
import { hasSuppression } from '../../parser/comment-analyzer.js';
import { matchesPattern } from '../../utils/pattern-matcher.js';

export const missingAuthCheckRule: Rule = {
  id: 'auth/missing-auth-check',
  name: 'Missing Authentication Check',
  category: 'auth',
  severity: 'high',
  description:
    'Convex functions should verify user authentication before performing operations',

  check(context: RuleContext): Finding[] {
    const { function: func, config } = context;

    const options = {
      checkQueries: true,
      checkMutations: true,
      checkActions: true,
      allowList: [] as string[],
      allowInlineSuppressions: true,
      ...(config?.options || {}),
    };

    // Skip internal functions (they don't need auth checks)
    if (isInternalFunction(func.type)) {
      return [];
    }

    const shouldCheck =
      (isMutation(func.type) && options.checkMutations) ||
      (isQuery(func.type) && options.checkQueries) ||
      (isAction(func.type) && options.checkActions);

    if (!shouldCheck) {
      return [];
    }

    if (
      options.allowList.length > 0 &&
      matchesPattern(func.name, options.allowList)
    ) {
      return [];
    }

    if (
      options.allowInlineSuppressions &&
      hasSuppression(func.node, 'allow-unauthenticated')
    ) {
      return [];
    }

    // Analyze ctx usage
    const ctxUsage = analyzeCtxUsage(func.node);

    // If the function uses ctx.auth, it's likely checking authentication
    if (ctxUsage.usesAuth) {
      return [];
    }

    const functionLabel = getFunctionLabel(func.type);

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
      message: `${functionLabel} '${func.name}' does not check user authentication`,
      remediation: generateRemediation(functionLabel),
      context: codeContext,
    };

    return [finding];
  },
};

function getFunctionLabel(functionType: ConvexFunctionType): string {
  if (isMutation(functionType)) {
    return 'Mutation';
  }

  if (isQuery(functionType)) {
    return 'Query';
  }

  if (functionType === 'httpAction') {
    return 'HTTP Action';
  }

  return 'Action';
}

function generateRemediation(functionLabel: string): string {
  return (
    `Add authentication check at the start of your ${functionLabel.toLowerCase()} handler:\n\n` +
    "const identity = await ctx.auth.getUserIdentity();\n" +
    "if (!identity) {\n" +
    "  throw new Error('Unauthenticated');\n" +
    "}\n\n" +
    "If intentionally public:\n" +
    "- Add: // @convex-scanner allow-unauthenticated\n" +
    "- Or configure allowList: ['signup*', 'login']"
  );
}
