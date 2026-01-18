import { describe, it, expect } from 'vitest';
import ts from 'typescript';
import { hasSuppression, extractSuppressions } from '../comment-analyzer.js';

function getFirstVariableDeclaration(code: string): ts.VariableDeclaration {
  const sourceFile = ts.createSourceFile(
    'fixture.ts',
    code,
    ts.ScriptTarget.ES2022,
    true,
    ts.ScriptKind.TS
  );

  let declaration: ts.VariableDeclaration | undefined;

  const visit = (node: ts.Node) => {
    if (!declaration && ts.isVariableDeclaration(node)) {
      declaration = node;
      return;
    }

    ts.forEachChild(node, visit);
  };

  visit(sourceFile);

  if (!declaration) {
    throw new Error('No variable declaration found in fixture');
  }

  return declaration;
}

describe('comment-analyzer', () => {
  it('detects suppression directive in line comment', () => {
    const code = `// @convex-scanner allow-unauthenticated
export const signup = mutation({
  handler: async () => {},
});
`;
    const declaration = getFirstVariableDeclaration(code);

    expect(hasSuppression(declaration, 'allow-unauthenticated')).toBe(true);
  });

  it('detects suppression directive in block comment', () => {
    const code = `/* @convex-scanner allow-unauthenticated */
export const signup = mutation({
  handler: async () => {},
});
`;
    const declaration = getFirstVariableDeclaration(code);

    expect(hasSuppression(declaration, 'allow-unauthenticated')).toBe(true);
  });

  it('matches suppression directives case-insensitively', () => {
    const code = `// @Convex-Scanner Allow-Unauthenticated
export const signup = mutation({
  handler: async () => {},
});
`;
    const declaration = getFirstVariableDeclaration(code);

    expect(hasSuppression(declaration, 'allow-unauthenticated')).toBe(true);
  });

  it('returns false for unrelated directives', () => {
    const code = `// @convex-scanner allow-something-else
export const signup = mutation({
  handler: async () => {},
});
`;
    const declaration = getFirstVariableDeclaration(code);

    expect(hasSuppression(declaration, 'allow-unauthenticated')).toBe(false);
    expect(extractSuppressions(declaration)).toEqual(['allow-something-else']);
  });
});
