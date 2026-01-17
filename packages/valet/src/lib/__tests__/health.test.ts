import { describe, it, expect } from 'vitest';
import { computeHealthState, getHealthStatus } from '../health';
import type { MoleStatusMetrics } from '../moleTypes';

describe('health', () => {
  const createMockMetrics = (overrides?: Partial<MoleStatusMetrics>): MoleStatusMetrics => ({
    cpu: {
      usage: 30,
      cores: 8,
      temperature: 50,
    },
    memory: {
      used: 8 * 1024 * 1024 * 1024, // 8GB
      total: 16 * 1024 * 1024 * 1024, // 16GB
      available: 8 * 1024 * 1024 * 1024, // 8GB
      percentage: 50,
    },
    disk: {
      used: 200 * 1024 * 1024 * 1024, // 200GB
      total: 500 * 1024 * 1024 * 1024, // 500GB
      available: 300 * 1024 * 1024 * 1024, // 300GB
      percentage: 40,
      mountPoint: '/',
    },
    network: {
      bytesReceived: 1024 * 1024,
      bytesSent: 1024 * 1024,
      packetsReceived: 1000,
      packetsSent: 1000,
    },
    timestamp: Date.now(),
    ...overrides,
  });

  describe('computeHealthState', () => {
    it('should return good status for healthy metrics', () => {
      const metrics = createMockMetrics();
      const health = computeHealthState(metrics);

      expect(health.status).toBe('good');
      expect(health.warnings).toHaveLength(0);
      expect(health.recommendations).toHaveLength(0);
    });

    it('should return critical status for low disk space (<10GB)', () => {
      const metrics = createMockMetrics({
        disk: {
          used: 490 * 1024 * 1024 * 1024,
          total: 500 * 1024 * 1024 * 1024,
          available: 5 * 1024 * 1024 * 1024, // 5GB
          percentage: 98,
          mountPoint: '/',
        },
      });
      const health = computeHealthState(metrics);

      expect(health.status).toBe('critical');
      expect(health.warnings.some((w) => w.includes('Disk space critically low'))).toBe(true);
      expect(health.recommendations.some((r) => r.includes('cleanup'))).toBe(true);
    });

    it('should return warning status for moderate disk space (10-20GB)', () => {
      const metrics = createMockMetrics({
        disk: {
          used: 485 * 1024 * 1024 * 1024,
          total: 500 * 1024 * 1024 * 1024,
          available: 15 * 1024 * 1024 * 1024, // 15GB
          percentage: 97,
          mountPoint: '/',
        },
      });
      const health = computeHealthState(metrics);

      expect(health.status).toBe('warning');
      expect(health.warnings.some((w) => w.includes('Disk space running low'))).toBe(true);
    });

    it('should return critical status for high CPU usage (>90%)', () => {
      const metrics = createMockMetrics({
        cpu: {
          usage: 95,
          cores: 8,
        },
      });
      const health = computeHealthState(metrics);

      expect(health.status).toBe('critical');
      expect(health.warnings.some((w) => w.includes('CPU usage critically high'))).toBe(true);
    });

    it('should return warning status for elevated CPU usage (>70%)', () => {
      const metrics = createMockMetrics({
        cpu: {
          usage: 75,
          cores: 8,
        },
      });
      const health = computeHealthState(metrics);

      expect(health.status).toBe('warning');
      expect(health.warnings.some((w) => w.includes('CPU usage elevated'))).toBe(true);
    });

    it('should return critical status for high memory usage (>90%)', () => {
      const metrics = createMockMetrics({
        memory: {
          used: 14.5 * 1024 * 1024 * 1024,
          total: 16 * 1024 * 1024 * 1024,
          available: 1.5 * 1024 * 1024 * 1024,
          percentage: 91,
        },
      });
      const health = computeHealthState(metrics);

      expect(health.status).toBe('critical');
      expect(health.warnings.some((w) => w.includes('Memory usage critically high'))).toBe(true);
    });

    it('should return warning status for elevated memory usage (>70%)', () => {
      const metrics = createMockMetrics({
        memory: {
          used: 12 * 1024 * 1024 * 1024,
          total: 16 * 1024 * 1024 * 1024,
          available: 4 * 1024 * 1024 * 1024,
          percentage: 75,
        },
      });
      const health = computeHealthState(metrics);

      expect(health.status).toBe('warning');
      expect(health.warnings.some((w) => w.includes('Memory usage elevated'))).toBe(true);
    });

    it('should prioritize critical over warning status', () => {
      const metrics = createMockMetrics({
        cpu: {
          usage: 95, // Critical
          cores: 8,
        },
        memory: {
          used: 12 * 1024 * 1024 * 1024,
          total: 16 * 1024 * 1024 * 1024,
          available: 4 * 1024 * 1024 * 1024,
          percentage: 75, // Warning
        },
      });
      const health = computeHealthState(metrics);

      expect(health.status).toBe('critical');
    });
  });

  describe('getHealthStatus', () => {
    it('should return simplified health status', () => {
      const goodMetrics = createMockMetrics();
      expect(getHealthStatus(goodMetrics)).toBe('good');

      const criticalMetrics = createMockMetrics({
        cpu: { usage: 95, cores: 8 },
      });
      expect(getHealthStatus(criticalMetrics)).toBe('critical');

      const warningMetrics = createMockMetrics({
        cpu: { usage: 75, cores: 8 },
      });
      expect(getHealthStatus(warningMetrics)).toBe('warning');
    });
  });
});
