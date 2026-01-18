/**
 * Context extractor - extracts surrounding code context for findings
 */

import ts from 'typescript';

/**
 * Extract code context around a node (3 lines before and after)
 */
export function extractContext(
  sourceFile: ts.SourceFile,
  node: ts.Node,
  linesBefore = 3,
  linesAfter = 3
): string {
  const { line } = sourceFile.getLineAndCharacterOfPosition(node.getStart());
  const sourceText = sourceFile.getFullText();
  const lines = sourceText.split('\n');

  const startLine = Math.max(0, line - linesBefore);
  const endLine = Math.min(lines.length - 1, line + linesAfter);

  const contextLines = lines.slice(startLine, endLine + 1);

  // Add line numbers
  return contextLines
    .map((lineText, idx) => {
      const lineNum = startLine + idx + 1;
      const marker = lineNum === line + 1 ? '>' : ' ';
      return `${marker} ${lineNum.toString().padStart(4, ' ')} | ${lineText}`;
    })
    .join('\n');
}

/**
 * Get the line and column position of a node
 */
export function getPosition(sourceFile: ts.SourceFile, node: ts.Node) {
  const start = sourceFile.getLineAndCharacterOfPosition(node.getStart());
  const end = sourceFile.getLineAndCharacterOfPosition(node.getEnd());

  return {
    line: start.line + 1, // Convert to 1-indexed
    column: start.character,
    endLine: end.line + 1,
    endColumn: end.character,
  };
}
