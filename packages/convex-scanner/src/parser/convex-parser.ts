/**
 * Convex Parser - TypeScript AST parsing for Convex files
 */

import ts from 'typescript';
import { readFileSync } from 'node:fs';

/**
 * Parsed Convex function information
 */
export interface ConvexFunction {
  name: string;
  type: ConvexFunctionType;
  filePath: string;
  node: ts.Node;
  sourceFile: ts.SourceFile;
  line: number;
  column: number;
  endLine: number;
  endColumn: number;
  argsSchema?: string;
  returnType?: string;
}

/**
 * Convex function types
 */
export type ConvexFunctionType =
  | 'query'
  | 'mutation'
  | 'action'
  | 'httpAction'
  | 'internalQuery'
  | 'internalMutation'
  | 'internalAction';

/**
 * Parser for Convex TypeScript files
 */
export class ConvexParser {
  private program: ts.Program;
  private checker: ts.TypeChecker;

  constructor(filePaths: string[]) {
    const compilerOptions: ts.CompilerOptions = {
      target: ts.ScriptTarget.ES2022,
      module: ts.ModuleKind.ES2022,
      moduleResolution: ts.ModuleResolutionKind.NodeNext,
      allowJs: false,
      strict: true,
      esModuleInterop: true,
    };

    this.program = ts.createProgram(filePaths, compilerOptions);
    this.checker = this.program.getTypeChecker();
  }

  /**
   * Parse a single file
   */
  parseFile(filePath: string): ConvexFunction[] {
    const sourceFile = this.program.getSourceFile(filePath);
    if (!sourceFile) {
      throw new Error(`Could not load source file: ${filePath}`);
    }

    const functions: ConvexFunction[] = [];

    const visit = (node: ts.Node) => {
      // Look for variable declarations that might be Convex functions
      if (ts.isVariableStatement(node)) {
        // Iterate through all declarations in the statement (e.g., const a = ..., b = ...)
        for (const declaration of node.declarationList.declarations) {
          if (
            ts.isVariableDeclaration(declaration) &&
            declaration.initializer
          ) {
            const functionType = this.detectConvexFunction(
              declaration.initializer
            );
            if (functionType && ts.isIdentifier(declaration.name)) {
              const { line, character } = sourceFile.getLineAndCharacterOfPosition(
                declaration.getStart()
              );
              const { line: endLine, character: endCharacter } =
                sourceFile.getLineAndCharacterOfPosition(declaration.getEnd());

              const metadata = this.extractFunctionMetadata(
                declaration.initializer
              );

              functions.push({
                name: declaration.name.text,
                type: functionType,
                filePath,
                node: declaration,
                sourceFile,
                line: line + 1, // Convert to 1-indexed
                column: character,
                endLine: endLine + 1,
                endColumn: endCharacter,
                argsSchema: metadata.argsSchema,
                returnType: metadata.returnType,
              });
            }
          }
        }
      }

      ts.forEachChild(node, visit);
    };

    visit(sourceFile);
    return functions;
  }

  /**
   * Detect if a call expression is a Convex function builder
   */
  private detectConvexFunction(
    node: ts.Expression
  ): ConvexFunctionType | null {
    if (!ts.isCallExpression(node)) {
      return null;
    }

    const expression = node.expression;

    // Direct calls: query(...), mutation(...), etc.
    if (ts.isIdentifier(expression)) {
      const name = expression.text;
      if (this.isConvexFunctionType(name)) {
        return name as ConvexFunctionType;
      }
    }

    // Property access: internal.query(...), internal.mutation(...), etc.
    if (ts.isPropertyAccessExpression(expression)) {
      const object = expression.expression;
      const property = expression.name.text;

      if (ts.isIdentifier(object) && object.text === 'internal') {
        const internalType = `internal${
          property.charAt(0).toUpperCase() + property.slice(1)
        }`;
        if (this.isConvexFunctionType(internalType)) {
          return internalType as ConvexFunctionType;
        }
      }
    }

    return null;
  }

  /**
   * Check if a name is a valid Convex function type
   */
  private isConvexFunctionType(name: string): boolean {
    return [
      'query',
      'mutation',
      'action',
      'httpAction',
      'internalQuery',
      'internalMutation',
      'internalAction',
    ].includes(name);
  }

  /**
   * Extract function metadata (args schema and return type)
   */
  private extractFunctionMetadata(node: ts.Expression): {
    argsSchema?: string;
    returnType?: string;
  } {
    const result: { argsSchema?: string; returnType?: string } = {};

    if (!ts.isCallExpression(node)) {
      return result;
    }

    const firstArg = node.arguments[0];
    if (!firstArg || !ts.isObjectLiteralExpression(firstArg)) {
      return result;
    }

    // Extract args schema
    for (const property of firstArg.properties) {
      if (
        ts.isPropertyAssignment(property) &&
        ts.isIdentifier(property.name)
      ) {
        if (property.name.text === 'args') {
          result.argsSchema = property.initializer.getText();
        } else if (property.name.text === 'returns') {
          result.returnType = property.initializer.getText();
        }
      }
    }

    // If no explicit returns, try to infer from handler
    if (!result.returnType) {
      for (const property of firstArg.properties) {
        if (
          ts.isPropertyAssignment(property) &&
          ts.isIdentifier(property.name) &&
          property.name.text === 'handler'
        ) {
          const handlerType = this.checker.getTypeAtLocation(
            property.initializer
          );
          const signatures = handlerType.getCallSignatures();
          if (signatures.length > 0) {
            const returnType = signatures[0]?.getReturnType();
            if (returnType) {
              result.returnType = this.checker.typeToString(returnType);
            }
          }
        }
      }
    }

    return result;
  }

  /**
   * Get TypeChecker for type analysis
   */
  getTypeChecker(): ts.TypeChecker {
    return this.checker;
  }

  /**
   * Get Program for advanced analysis
   */
  getProgram(): ts.Program {
    return this.program;
  }
}
