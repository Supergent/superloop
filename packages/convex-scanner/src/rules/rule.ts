/**
 * Rule interface and context
 */

import type ts from 'typescript';
import type { Finding, FindingCategory, FindingSeverity } from '../types.js';
import type { ConvexFunction } from '../parser/convex-parser.js';

/**
 * Context provided to rules for analysis
 */
export interface RuleContext {
  /** The Convex function being analyzed */
  function: ConvexFunction;
  /** TypeScript type checker */
  typeChecker: ts.TypeChecker;
  /** Full TypeScript program */
  program: ts.Program;
}

/**
 * Rule interface
 */
export interface Rule {
  /** Unique rule ID */
  id: string;
  /** Human-readable name */
  name: string;
  /** Category of issues this rule detects */
  category: FindingCategory;
  /** Default severity */
  severity: FindingSeverity;
  /** Description of what the rule checks */
  description: string;
  /** Execute the rule check */
  check(context: RuleContext): Finding[];
}

/**
 * Rule configuration
 */
export interface RuleConfiguration {
  enabled: boolean;
  severity: FindingSeverity;
}
