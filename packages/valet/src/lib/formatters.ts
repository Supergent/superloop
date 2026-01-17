/**
 * Human-readable formatting utilities for system metrics
 */

/**
 * Format bytes to human-readable string (B, KB, MB, GB, TB)
 */
export function formatBytes(bytes: number, decimals?: number): string {
  if (bytes === 0) return '0 B';

  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];

  const i = Math.floor(Math.log(bytes) / Math.log(k));
  const value = bytes / Math.pow(k, i);

  // If the value is a whole number, show it without decimals
  if (Number.isInteger(value)) {
    return `${value} ${sizes[i]}`;
  }

  // Determine if decimals were explicitly provided
  const isExplicit = decimals !== undefined;
  const dm = decimals === undefined ? 2 : (decimals < 0 ? 0 : decimals);

  // Format with the specified decimal places
  const formatted = value.toFixed(dm);

  // If using default decimals, strip trailing zeros
  // If decimals were explicitly provided, preserve them
  const cleanValue = isExplicit ? formatted : formatted.replace(/\.?0+$/, '');

  return `${cleanValue} ${sizes[i]}`;
}

/**
 * Format percentage with specified decimal places
 */
export function formatPercentage(value: number, decimals: number = 1): string {
  return `${value.toFixed(decimals)}%`;
}

/**
 * Format network rate (bytes per second)
 */
export function formatRate(bytesPerSecond: number): string {
  return `${formatBytes(bytesPerSecond)}/s`;
}

/**
 * Format timestamp to relative time (e.g., "2m ago", "3h ago")
 */
export function formatRelativeTime(timestamp: number): string {
  const now = Date.now();
  const diff = now - timestamp;

  const seconds = Math.floor(diff / 1000);
  const minutes = Math.floor(diff / 60000);
  const hours = Math.floor(diff / 3600000);
  const days = Math.floor(diff / 86400000);

  if (seconds < 60) return 'Just now';
  if (minutes < 60) return `${minutes}m ago`;
  if (hours < 24) return `${hours}h ago`;
  return `${days}d ago`;
}

/**
 * Format timestamp to human-readable date/time
 */
export function formatDateTime(timestamp: number): string {
  const date = new Date(timestamp);
  return date.toLocaleString();
}

/**
 * Format duration in milliseconds to human-readable string
 */
export function formatDuration(milliseconds: number): string {
  const seconds = Math.floor(milliseconds / 1000);
  const minutes = Math.floor(seconds / 60);
  const hours = Math.floor(minutes / 60);

  if (hours > 0) {
    return `${hours}h ${minutes % 60}m`;
  }
  if (minutes > 0) {
    return `${minutes}m ${seconds % 60}s`;
  }
  return `${seconds}s`;
}
