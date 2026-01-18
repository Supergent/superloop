/**
 * Validator parser - extracts and analyzes Convex validators
 */

import ts from 'typescript';

/**
 * Validator information
 */
export interface ValidatorInfo {
  hasValidator: boolean;
  validatorNode?: ts.Node;
  validatorType?: string;
  argsSchema?: string;
  returnType?: string;
}

/**
 * Parse validator from function arguments
 */
export function parseValidator(node: ts.CallExpression): ValidatorInfo {
  const result: ValidatorInfo = {
    hasValidator: false,
  };

  // Convex functions typically have an object literal as first argument
  // with 'args' and 'handler' properties
  const firstArg = node.arguments[0];
  if (!firstArg || !ts.isObjectLiteralExpression(firstArg)) {
    return result;
  }

  // Look for 'args' and 'returns' properties
  for (const property of firstArg.properties) {
    if (
      ts.isPropertyAssignment(property) &&
      ts.isIdentifier(property.name)
    ) {
      if (property.name.text === 'args') {
        result.hasValidator = true;
        result.validatorNode = property.initializer;
        result.validatorType = getValidatorType(property.initializer);
        result.argsSchema = property.initializer.getText();
      } else if (property.name.text === 'returns') {
        result.returnType = property.initializer.getText();
      }
    }
  }

  return result;
}

/**
 * Determine the type of validator
 */
function getValidatorType(node: ts.Expression): string {
  if (ts.isCallExpression(node)) {
    const expression = node.expression;

    // v.object(...), v.string(), etc.
    if (ts.isPropertyAccessExpression(expression)) {
      const object = expression.expression;
      const method = expression.name.text;

      if (ts.isIdentifier(object) && object.text === 'v') {
        return `v.${method}`;
      }
    }
  }

  if (ts.isObjectLiteralExpression(node)) {
    return 'object-literal';
  }

  return 'unknown';
}

/**
 * Check if a validator is present
 */
export function hasValidator(node: ts.CallExpression): boolean {
  const info = parseValidator(node);
  return info.hasValidator;
}
