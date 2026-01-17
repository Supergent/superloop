/**
 * TypeScript type definitions for Mole CLI command outputs
 */

// ============================================================================
// mo status - Real-time system metrics
// ============================================================================

export interface MoleStatusMetrics {
  cpu: CpuMetrics;
  memory: MemoryMetrics;
  disk: DiskMetrics;
  network: NetworkMetrics;
  timestamp: number;
}

export interface CpuMetrics {
  usage: number; // Percentage 0-100
  cores: number;
  temperature?: number; // Celsius
}

export interface MemoryMetrics {
  used: number; // Bytes
  total: number; // Bytes
  available: number; // Bytes
  percentage: number; // 0-100
  swap?: {
    used: number;
    total: number;
  };
}

export interface DiskMetrics {
  used: number; // Bytes
  total: number; // Bytes
  available: number; // Bytes
  percentage: number; // 0-100
  mountPoint: string;
}

export interface NetworkMetrics {
  bytesReceived: number;
  bytesSent: number;
  packetsReceived: number;
  packetsSent: number;
}

// ============================================================================
// mo analyze - Disk space visualization
// ============================================================================

export interface MoleAnalyzeResult {
  directories: DirectoryInfo[];
  totalSize: number;
  scanPath: string;
  timestamp: number;
}

export interface DirectoryInfo {
  path: string;
  size: number; // Bytes
  percentage: number; // Of total
  fileCount: number;
}

// ============================================================================
// mo clean - Cache/log cleanup
// ============================================================================

export interface MoleCleanResult {
  itemsRemoved: number;
  spaceRecovered: number; // Bytes
  categories: CleanCategory[];
  dryRun: boolean;
  timestamp: number;
}

export interface CleanCategory {
  name: string; // e.g., "System Caches", "Application Caches", "Logs"
  itemsRemoved: number;
  spaceRecovered: number; // Bytes
  files: string[];
}

// ============================================================================
// mo uninstall - Complete app removal
// ============================================================================

export interface MoleUninstallResult {
  appName: string;
  success: boolean;
  spaceRecovered: number; // Bytes
  itemsRemoved: UninstallItem[];
  timestamp: number;
}

export interface UninstallItem {
  type: 'application' | 'cache' | 'preferences' | 'login_items' | 'other';
  path: string;
  size: number; // Bytes
}

// ============================================================================
// mo optimize - System optimization
// ============================================================================

export interface MoleOptimizeResult {
  tasksCompleted: OptimizeTask[];
  dryRun: boolean;
  requiresSudo: boolean;
  timestamp: number;
}

export interface OptimizeTask {
  name: string;
  description: string;
  success: boolean;
  impact?: string; // Description of what was improved
  error?: string;
}

// ============================================================================
// mo purge - Developer artifact cleanup
// ============================================================================

export interface MolePurgeResult {
  artifactsFound: DeveloperArtifact[];
  totalSize: number; // Bytes
  spaceRecovered: number; // Bytes (if not dry run)
  dryRun: boolean;
  timestamp: number;
}

export interface DeveloperArtifact {
  type: 'node_modules' | 'build' | '.next' | 'dist' | 'target' | 'other';
  path: string;
  size: number; // Bytes
  projectName?: string;
}

// ============================================================================
// mo installer - Installer file cleanup
// ============================================================================

export interface MoleInstallerResult {
  installersFound: InstallerFile[];
  totalSize: number; // Bytes
  spaceRecovered: number; // Bytes (if not dry run)
  dryRun: boolean;
  timestamp: number;
}

export interface InstallerFile {
  path: string;
  size: number; // Bytes
  type: string; // e.g., ".dmg", ".pkg", ".zip"
  name: string;
}

// ============================================================================
// Common types
// ============================================================================

export interface MoleCommandOptions {
  dryRun?: boolean;
  debug?: boolean;
}

export interface MoleError {
  command: string;
  message: string;
  code?: number;
  stderr?: string;
}

// ============================================================================
// Health status (for menubar icon)
// ============================================================================

export type HealthStatus = 'good' | 'warning' | 'critical';

export interface SystemHealth {
  status: HealthStatus;
  metrics: MoleStatusMetrics;
  warnings: string[];
  recommendations: string[];
}

export function getHealthStatus(metrics: MoleStatusMetrics): HealthStatus {
  const diskGb = metrics.disk.available / (1024 * 1024 * 1024);

  if (diskGb < 10 || metrics.cpu.usage > 90 || metrics.memory.percentage > 90) {
    return 'critical';
  }

  if (diskGb < 20 || metrics.cpu.usage > 70 || metrics.memory.percentage > 70) {
    return 'warning';
  }

  return 'good';
}

// ============================================================================
// Utility functions
// ============================================================================

export function formatBytes(bytes: number): string {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let size = bytes;
  let unitIndex = 0;

  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex++;
  }

  return `${size.toFixed(2)} ${units[unitIndex]}`;
}

export function formatPercentage(value: number): string {
  return `${value.toFixed(1)}%`;
}
