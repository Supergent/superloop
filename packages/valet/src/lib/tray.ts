/**
 * Tray icon management utilities
 * Updates tray tooltip (and icon if supported) based on health state
 */

import { invoke } from '@tauri-apps/api/core';
import { HealthStatus, SystemHealth } from './moleTypes';
import { formatBytes, formatPercentage } from './formatters';

/**
 * Update the tray tooltip with current system status
 */
export async function updateTrayTooltip(
  health: SystemHealth,
  lastUpdate?: string | null
): Promise<void> {
  try {
    const tooltip = buildTooltipText(health, lastUpdate);
    await invoke('update_tray_tooltip', { tooltip });
  } catch (error) {
    console.error('Failed to update tray tooltip:', error);
  }
}

/**
 * Update the tray icon based on health status and AI working state
 */
export async function updateTrayIcon(
  status: HealthStatus,
  isAiWorking?: boolean
): Promise<void> {
  try {
    await invoke('update_tray_icon', {
      status,
      isAiWorking: isAiWorking || false
    });
  } catch (error) {
    console.error('Failed to update tray icon:', error);
  }
}

/**
 * Build tooltip text from system health data
 */
function buildTooltipText(health: SystemHealth, lastUpdate?: string | null): string {
  const { status, metrics, warnings } = health;

  const lines: string[] = [
    `Valet - ${getStatusLabel(status)}`,
  ];

  // Add last update timestamp if available
  if (lastUpdate) {
    const updateDate = new Date(lastUpdate);
    const now = new Date();
    const diffMinutes = Math.floor((now.getTime() - updateDate.getTime()) / 60000);

    if (diffMinutes < 1) {
      lines.push('Updated just now');
    } else if (diffMinutes < 60) {
      lines.push(`Updated ${diffMinutes}m ago`);
    } else {
      const hours = Math.floor(diffMinutes / 60);
      lines.push(`Updated ${hours}h ago`);
    }
  }

  lines.push('');
  lines.push(`CPU: ${formatPercentage(metrics.cpu.usage)}`);
  lines.push(`Memory: ${formatPercentage(metrics.memory.percentage)}`);
  lines.push(`Disk: ${formatBytes(metrics.disk.available)} available`);

  if (warnings.length > 0) {
    lines.push('');
    lines.push(...warnings);
  }

  return lines.join('\n');
}

/**
 * Get human-readable status label
 */
function getStatusLabel(status: HealthStatus): string {
  switch (status) {
    case 'good':
      return 'Healthy';
    case 'warning':
      return 'Warning';
    case 'critical':
      return 'Critical';
  }
}

/**
 * Update both tooltip and icon based on system health
 */
export async function updateTray(
  health: SystemHealth,
  lastUpdate?: string | null,
  isAiWorking?: boolean
): Promise<void> {
  await Promise.all([
    updateTrayTooltip(health, lastUpdate),
    updateTrayIcon(health.status, isAiWorking),
  ]);
}
