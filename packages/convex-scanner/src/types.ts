/**
 * Core types for the Convex Security Scanner
 */

/**
 * Category of a security finding
 */
export type FindingCategory = 'auth' | 'validation' | 'exposure' | 'general';

/**
 * Severity level of a security finding
 */
export type FindingSeverity = 'critical' | 'high' | 'medium' | 'low' | 'info';

/**
 * A security finding from the scanner
 */
export interface Finding {
  /** File path where the finding was detected */
  file: string;
  /** Starting line number (1-indexed) */
  line: number;
  /** Starting column number (0-indexed) */
  column: number;
  /** Ending line number (1-indexed) */
  endLine: number;
  /** Ending column number (0-indexed) */
  endColumn: number;
  /** Rule ID that generated this finding */
  rule: string;
  /** Category of the finding */
  category: FindingCategory;
  /** Severity level */
  severity: FindingSeverity;
  /** Human-readable message describing the issue */
  message: string;
  /** Suggested remediation/fix */
  remediation: string;
  /** Code context (surrounding lines) */
  context: string;
}

/**
 * Error encountered during scanning
 */
export interface ScanError {
  /** File where the error occurred */
  file: string;
  /** Error message */
  message: string;
  /** Stack trace if available */
  stack?: string;
}

/**
 * Metadata about the scan execution
 */
export interface ScanMetadata {
  /** Timestamp when scan started */
  timestamp: string;
  /** Number of files scanned */
  filesScanned: number;
  /** Number of files with findings */
  filesWithFindings: number;
  /** Rules that were executed */
  rulesRun: string[];
  /** Scanner version */
  scannerVersion: string;
  /** Scan duration in milliseconds */
  durationMs: number;
}

/**
 * Complete scan result
 */
export interface ScanResult {
  /** All findings discovered */
  findings: Finding[];
  /** List of files that were scanned */
  scannedFiles: string[];
  /** Errors encountered during scanning */
  errors: ScanError[];
  /** Scan metadata */
  metadata: ScanMetadata;
}

/**
 * Options for scanning
 */
export interface ScanOptions {
  /** Path(s) to Convex directory/directories */
  convexDir?: string | string[];
  /** Configuration file path (defaults to searching for convex-scanner.config.ts) */
  configPath?: string;
  /** Output format */
  format?: 'json' | 'markdown';
  /** Rule configuration overrides */
  rules?: Record<string, { enabled?: boolean; severity?: FindingSeverity }>;
  /** Additional ignore patterns */
  ignore?: string[];
  /**
   * Whether to throw on config/discovery errors or return them in ScanResult.errors
   * @default true - throws on errors
   * When false, errors are collected and returned in ScanResult.errors
   */
  throwOnError?: boolean;
}
