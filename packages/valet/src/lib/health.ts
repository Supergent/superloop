import { HealthStatus, MoleStatusMetrics, SystemHealth } from './moleTypes';
import { DEFAULT_DISK_WARNING_THRESHOLD, DEFAULT_DISK_CRITICAL_THRESHOLD } from './settings';

/**
 * Default thresholds for disk space in GB
 * Can be overridden via settings
 */
const DISK_CRITICAL_GB = DEFAULT_DISK_CRITICAL_THRESHOLD;
const DISK_WARNING_GB = DEFAULT_DISK_WARNING_THRESHOLD;

/**
 * Thresholds for CPU usage (percentage)
 */
const CPU_CRITICAL = 90;
const CPU_WARNING = 70;

/**
 * Thresholds for memory usage (percentage)
 */
const MEMORY_CRITICAL = 90;
const MEMORY_WARNING = 70;

/**
 * Computes health state (healthy/warning/critical) from system metrics.
 * Uses disk thresholds and resource usage to determine overall system health.
 *
 * @param metrics - System metrics from Mole
 * @param diskWarningThreshold - Optional custom warning threshold in GB (default: 20)
 * @param diskCriticalThreshold - Optional custom critical threshold in GB (default: 10)
 */
export function computeHealthState(
  metrics: MoleStatusMetrics,
  diskWarningThreshold: number = DISK_WARNING_GB,
  diskCriticalThreshold: number = DISK_CRITICAL_GB
): SystemHealth {
  const diskGb = metrics.disk.available / (1024 * 1024 * 1024);
  const warnings: string[] = [];
  const recommendations: string[] = [];

  let status: HealthStatus = 'good';

  // Check critical conditions
  if (diskGb < diskCriticalThreshold) {
    status = 'critical';
    warnings.push(`Disk space critically low: ${diskGb.toFixed(1)} GB available`);
    recommendations.push('Run cleanup or remove large files immediately');
  }

  if (metrics.cpu.usage > CPU_CRITICAL) {
    status = 'critical';
    warnings.push(`CPU usage critically high: ${metrics.cpu.usage.toFixed(1)}%`);
    recommendations.push('Close resource-intensive applications');
  }

  if (metrics.memory.percentage > MEMORY_CRITICAL) {
    status = 'critical';
    warnings.push(`Memory usage critically high: ${metrics.memory.percentage.toFixed(1)}%`);
    recommendations.push('Close unused applications to free memory');
  }

  // Check warning conditions (only if not already critical)
  if (status !== 'critical') {
    if (diskGb < diskWarningThreshold) {
      status = 'warning';
      warnings.push(`Disk space running low: ${diskGb.toFixed(1)} GB available`);
      recommendations.push('Consider running cleanup soon');
    }

    if (metrics.cpu.usage > CPU_WARNING) {
      status = 'warning';
      warnings.push(`CPU usage elevated: ${metrics.cpu.usage.toFixed(1)}%`);
      recommendations.push('Monitor resource-intensive applications');
    }

    if (metrics.memory.percentage > MEMORY_WARNING) {
      status = 'warning';
      warnings.push(`Memory usage elevated: ${metrics.memory.percentage.toFixed(1)}%`);
      recommendations.push('Consider closing some applications');
    }
  }

  return {
    status,
    metrics,
    warnings,
    recommendations,
  };
}

/**
 * Get health status from metrics (simpler version)
 *
 * @param metrics - System metrics from Mole
 * @param diskWarningThreshold - Optional custom warning threshold in GB
 * @param diskCriticalThreshold - Optional custom critical threshold in GB
 */
export function getHealthStatus(
  metrics: MoleStatusMetrics,
  diskWarningThreshold?: number,
  diskCriticalThreshold?: number
): HealthStatus {
  return computeHealthState(metrics, diskWarningThreshold, diskCriticalThreshold).status;
}
