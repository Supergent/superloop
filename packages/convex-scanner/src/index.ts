/**
 * Convex Security Scanner - Main Entry Point
 *
 * Static security analysis tool for Convex backend code
 */

export type {
  Finding,
  FindingCategory,
  FindingSeverity,
  ScanError,
  ScanMetadata,
  ScanResult,
  ScanOptions,
} from './types.js';

export { scanConvex } from './scanner/static-scanner.js';
