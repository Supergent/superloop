/**
 * Schema parser - extracts schema definitions from schema.ts
 */

import ts from 'typescript';

/**
 * Table information from schema
 */
export interface TableInfo {
  name: string;
  node: ts.Node;
  validators: string[];
  indexes: string[];
}

/**
 * Schema information
 */
export interface SchemaInfo {
  tables: TableInfo[];
}

/**
 * Parse schema definitions from a file
 */
export function parseSchema(sourceFile: ts.SourceFile): SchemaInfo {
  const schema: SchemaInfo = {
    tables: [],
  };

  const visit = (node: ts.Node) => {
    // Look for schema definition patterns
    // Typically: export default defineSchema({ tableName: defineTable({ ... }) })
    if (ts.isCallExpression(node)) {
      const expression = node.expression;

      // Check for defineSchema call
      if (ts.isIdentifier(expression) && expression.text === 'defineSchema') {
        const schemaArg = node.arguments[0];
        if (schemaArg && ts.isObjectLiteralExpression(schemaArg)) {
          parseSchemaTables(schemaArg, schema);
        }
      }
    }

    ts.forEachChild(node, visit);
  };

  visit(sourceFile);
  return schema;
}

/**
 * Parse tables from schema object
 */
function parseSchemaTables(
  schemaObject: ts.ObjectLiteralExpression,
  schema: SchemaInfo
): void {
  for (const property of schemaObject.properties) {
    if (
      ts.isPropertyAssignment(property) &&
      ts.isIdentifier(property.name)
    ) {
      const tableName = property.name.text;
      const tableDefinition = property.initializer;

      if (ts.isCallExpression(tableDefinition)) {
        const table: TableInfo = {
          name: tableName,
          node: property,
          validators: [],
          indexes: [],
        };

        // Parse table definition
        parseTableDefinition(tableDefinition, table);
        schema.tables.push(table);
      }
    }
  }
}

/**
 * Parse table definition details
 */
function parseTableDefinition(
  node: ts.CallExpression,
  table: TableInfo
): void {
  // Extract the base defineTable call
  const baseCall = findBaseDefineTableCall(node);

  // Parse validators from the base defineTable call
  const firstArg = baseCall.arguments[0];
  if (firstArg && ts.isObjectLiteralExpression(firstArg)) {
    for (const prop of firstArg.properties) {
      if (ts.isPropertyAssignment(prop) && ts.isIdentifier(prop.name)) {
        table.validators.push(prop.name.text);
      }
    }
  }

  // Walk the chain to extract index names
  extractIndexesFromChain(node, table);
}

/**
 * Find the base defineTable call by walking up the chain
 */
function findBaseDefineTableCall(node: ts.CallExpression): ts.CallExpression {
  let current = node;

  // Walk down to the base call
  while (
    ts.isPropertyAccessExpression(current.expression) &&
    ts.isCallExpression(current.expression.expression)
  ) {
    current = current.expression.expression;
  }

  return current;
}

/**
 * Extract index names from chained .index()/.searchIndex()/.vectorIndex() calls
 */
function extractIndexesFromChain(node: ts.CallExpression, table: TableInfo): void {
  const indexMethodNames = ['index', 'searchIndex', 'vectorIndex'];

  // Walk the entire chain
  let current: ts.Node = node;

  while (ts.isCallExpression(current)) {
    const expr = current.expression;

    // Check if this is a chained method call like .index(...)
    if (ts.isPropertyAccessExpression(expr)) {
      const methodName = expr.name.text;

      if (indexMethodNames.includes(methodName)) {
        // First argument is the index name
        const indexNameArg = current.arguments[0];
        if (indexNameArg && ts.isStringLiteral(indexNameArg)) {
          table.indexes.push(indexNameArg.text);
        }
      }

      // Continue walking down the chain
      if (ts.isCallExpression(expr.expression)) {
        current = expr.expression;
      } else {
        break;
      }
    } else {
      // No more chained calls
      break;
    }
  }
}

/**
 * Find table by name in schema
 */
export function findTable(
  schema: SchemaInfo,
  tableName: string
): TableInfo | undefined {
  return schema.tables.find((t) => t.name === tableName);
}
