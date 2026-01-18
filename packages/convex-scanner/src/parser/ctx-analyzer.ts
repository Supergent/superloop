/**
 * Context (ctx) usage analyzer
 */

import ts from 'typescript';

/**
 * Context usage information
 */
export interface CtxUsage {
  usesAuth: boolean;
  usesDb: boolean;
  usesStorage: boolean;
  usesScheduler: boolean;
  authUsageNodes: ts.Node[];
}

/**
 * Analyze ctx object usage in a function
 */
export function analyzeCtxUsage(node: ts.Node): CtxUsage {
  const usage: CtxUsage = {
    usesAuth: false,
    usesDb: false,
    usesStorage: false,
    usesScheduler: false,
    authUsageNodes: [],
  };

  const visit = (n: ts.Node) => {
    // Look for property access expressions like ctx.auth, ctx.db, etc.
    if (ts.isPropertyAccessExpression(n)) {
      const object = n.expression;
      const property = n.name.text;

      // Check if this is accessing 'ctx'
      if (ts.isIdentifier(object) && object.text === 'ctx') {
        switch (property) {
          case 'auth':
            usage.usesAuth = true;
            usage.authUsageNodes.push(n);
            break;
          case 'db':
            usage.usesDb = true;
            break;
          case 'storage':
            usage.usesStorage = true;
            break;
          case 'scheduler':
            usage.usesScheduler = true;
            break;
        }
      }

      // Also check for chained access like ctx.auth.getUserIdentity()
      if (
        ts.isPropertyAccessExpression(object) &&
        ts.isIdentifier(object.expression) &&
        object.expression.text === 'ctx'
      ) {
        const parentProperty = object.name.text;
        switch (parentProperty) {
          case 'auth':
            usage.usesAuth = true;
            usage.authUsageNodes.push(object);
            break;
          case 'db':
            usage.usesDb = true;
            break;
          case 'storage':
            usage.usesStorage = true;
            break;
          case 'scheduler':
            usage.usesScheduler = true;
            break;
        }
      }
    }

    ts.forEachChild(n, visit);
  };

  visit(node);
  return usage;
}

/**
 * Check if a function has auth checks
 */
export function hasAuthCheck(node: ts.Node): boolean {
  const usage = analyzeCtxUsage(node);
  return usage.usesAuth;
}
