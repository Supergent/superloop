/**
 * Comment analyzer for suppression directives
 */

import ts from 'typescript';

const SUPPRESSION_REGEX = /@convex-scanner\s+([a-z0-9-]+)/gi;

/**
 * Get the leading comments for a node.
 */
export function getLeadingComments(
  node: ts.Node,
  sourceFile: ts.SourceFile
): string[] {
  const text = sourceFile.getFullText();
  const seen = new Set<string>();
  const comments: string[] = [];

  const addRanges = (ranges: ts.CommentRange[] | undefined): void => {
    if (!ranges) {
      return;
    }

    for (const range of ranges) {
      const key = `${range.pos}:${range.end}`;
      if (seen.has(key)) {
        continue;
      }
      seen.add(key);
      comments.push(text.slice(range.pos, range.end).trim());
    }
  };

  addRanges(ts.getLeadingCommentRanges(text, node.getFullStart()));

  if (
    ts.isVariableDeclaration(node) &&
    ts.isVariableDeclarationList(node.parent) &&
    ts.isVariableStatement(node.parent.parent)
  ) {
    addRanges(
      ts.getLeadingCommentRanges(
        text,
        node.parent.parent.getFullStart()
      )
    );
  }

  return comments;
}

/**
 * Extract suppression directives from a node's leading comments.
 */
export function extractSuppressions(node: ts.Node): string[] {
  const sourceFile = node.getSourceFile();
  const comments = getLeadingComments(node, sourceFile);
  const suppressions: string[] = [];

  for (const comment of comments) {
    for (const match of comment.matchAll(SUPPRESSION_REGEX)) {
      const directive = match[1];
      if (directive) {
        suppressions.push(directive.toLowerCase());
      }
    }
  }

  return suppressions;
}

/**
 * Check if a suppression directive is present on a node.
 */
export function hasSuppression(node: ts.Node, directive: string): boolean {
  const target = directive.toLowerCase();
  return extractSuppressions(node).includes(target);
}
