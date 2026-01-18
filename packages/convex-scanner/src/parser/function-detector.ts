/**
 * Function detector - identifies Convex function patterns
 */

import ts from 'typescript';
import type { ConvexFunctionType } from './convex-parser.js';

/**
 * Detect Convex function type from an expression
 */
export function detectFunctionType(
  node: ts.Expression
): ConvexFunctionType | null {
  if (!ts.isCallExpression(node)) {
    return null;
  }

  const expression = node.expression;

  // Direct calls: query(...), mutation(...), etc.
  if (ts.isIdentifier(expression)) {
    return identifierToFunctionType(expression.text);
  }

  // Property access: internal.query(...), internal.mutation(...), etc.
  if (ts.isPropertyAccessExpression(expression)) {
    const object = expression.expression;
    const property = expression.name.text;

    if (ts.isIdentifier(object) && object.text === 'internal') {
      const internalType = `internal${
        property.charAt(0).toUpperCase() + property.slice(1)
      }`;
      return identifierToFunctionType(internalType);
    }
  }

  return null;
}

/**
 * Convert identifier text to function type
 */
function identifierToFunctionType(
  name: string
): ConvexFunctionType | null {
  const validTypes: ConvexFunctionType[] = [
    'query',
    'mutation',
    'action',
    'httpAction',
    'internalQuery',
    'internalMutation',
    'internalAction',
  ];

  return validTypes.includes(name as ConvexFunctionType)
    ? (name as ConvexFunctionType)
    : null;
}

/**
 * Check if a function type is internal
 */
export function isInternalFunction(type: ConvexFunctionType): boolean {
  return type.startsWith('internal');
}

/**
 * Check if a function type is a mutation
 */
export function isMutation(type: ConvexFunctionType): boolean {
  return type === 'mutation' || type === 'internalMutation';
}

/**
 * Check if a function type is a query
 */
export function isQuery(type: ConvexFunctionType): boolean {
  return type === 'query' || type === 'internalQuery';
}

/**
 * Check if a function type is an action
 */
export function isAction(type: ConvexFunctionType): boolean {
  return type === 'action' || type === 'internalAction';
}
