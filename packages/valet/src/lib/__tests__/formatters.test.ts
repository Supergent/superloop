import { describe, it, expect } from 'vitest';
import {
  formatBytes,
  formatPercentage,
  formatRate,
  formatRelativeTime,
  formatDuration,
} from '../formatters';

describe('formatters', () => {
  describe('formatBytes', () => {
    it('should format 0 bytes', () => {
      expect(formatBytes(0)).toBe('0 B');
    });

    it('should format bytes', () => {
      expect(formatBytes(500)).toBe('500 B');
    });

    it('should format kilobytes', () => {
      expect(formatBytes(1024)).toBe('1 KB');
      expect(formatBytes(2048)).toBe('2 KB');
    });

    it('should format megabytes', () => {
      expect(formatBytes(1024 * 1024)).toBe('1 MB');
      expect(formatBytes(5 * 1024 * 1024)).toBe('5 MB');
    });

    it('should format gigabytes', () => {
      expect(formatBytes(1024 * 1024 * 1024)).toBe('1 GB');
      expect(formatBytes(10.5 * 1024 * 1024 * 1024)).toBe('10.5 GB');
    });

    it('should format terabytes', () => {
      expect(formatBytes(1024 * 1024 * 1024 * 1024)).toBe('1 TB');
    });

    it('should respect decimal places parameter', () => {
      expect(formatBytes(1536, 0)).toBe('2 KB'); // 1.5 KB rounded
      expect(formatBytes(1536, 1)).toBe('1.5 KB');
      expect(formatBytes(1536, 3)).toBe('1.500 KB');
    });
  });

  describe('formatPercentage', () => {
    it('should format percentages with default decimals', () => {
      expect(formatPercentage(50)).toBe('50.0%');
      expect(formatPercentage(75.5)).toBe('75.5%');
    });

    it('should format percentages with custom decimals', () => {
      expect(formatPercentage(50, 0)).toBe('50%');
      expect(formatPercentage(75.5555, 2)).toBe('75.56%');
    });
  });

  describe('formatRate', () => {
    it('should format bytes per second', () => {
      expect(formatRate(1024)).toBe('1 KB/s');
      expect(formatRate(1024 * 1024)).toBe('1 MB/s');
      expect(formatRate(5 * 1024 * 1024)).toBe('5 MB/s');
    });
  });

  describe('formatRelativeTime', () => {
    const now = Date.now();

    it('should format "Just now" for recent timestamps', () => {
      expect(formatRelativeTime(now)).toBe('Just now');
      expect(formatRelativeTime(now - 30000)).toBe('Just now'); // 30 seconds ago
    });

    it('should format minutes ago', () => {
      expect(formatRelativeTime(now - 60000)).toBe('1m ago'); // 1 minute
      expect(formatRelativeTime(now - 300000)).toBe('5m ago'); // 5 minutes
      expect(formatRelativeTime(now - 3540000)).toBe('59m ago'); // 59 minutes
    });

    it('should format hours ago', () => {
      expect(formatRelativeTime(now - 3600000)).toBe('1h ago'); // 1 hour
      expect(formatRelativeTime(now - 7200000)).toBe('2h ago'); // 2 hours
      expect(formatRelativeTime(now - 82800000)).toBe('23h ago'); // 23 hours
    });

    it('should format days ago', () => {
      expect(formatRelativeTime(now - 86400000)).toBe('1d ago'); // 1 day
      expect(formatRelativeTime(now - 172800000)).toBe('2d ago'); // 2 days
      expect(formatRelativeTime(now - 604800000)).toBe('7d ago'); // 7 days
    });
  });

  describe('formatDuration', () => {
    it('should format seconds', () => {
      expect(formatDuration(5000)).toBe('5s');
      expect(formatDuration(30000)).toBe('30s');
      expect(formatDuration(59000)).toBe('59s');
    });

    it('should format minutes and seconds', () => {
      expect(formatDuration(60000)).toBe('1m 0s');
      expect(formatDuration(90000)).toBe('1m 30s');
      expect(formatDuration(3540000)).toBe('59m 0s');
    });

    it('should format hours and minutes', () => {
      expect(formatDuration(3600000)).toBe('1h 0m');
      expect(formatDuration(3660000)).toBe('1h 1m');
      expect(formatDuration(7200000)).toBe('2h 0m');
    });
  });
});
