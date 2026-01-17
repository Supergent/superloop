import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MetricsDisplay } from '../MetricsDisplay';
import type { MoleStatusMetrics } from '../../lib/moleTypes';

describe('MetricsDisplay', () => {
  const mockMetrics: MoleStatusMetrics = {
    cpu: {
      usage: 45.5,
      cores: 8,
      temperature: 55,
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
      bytesReceived: 5 * 1024 * 1024, // 5MB
      bytesSent: 2 * 1024 * 1024, // 2MB
      packetsReceived: 5000,
      packetsSent: 3000,
    },
    timestamp: Date.now(),
  };

  it('should render all metric cards', () => {
    render(<MetricsDisplay metrics={mockMetrics} />);

    expect(screen.getByText('CPU')).toBeInTheDocument();
    expect(screen.getByText('Memory')).toBeInTheDocument();
    expect(screen.getByText('Disk')).toBeInTheDocument();
    expect(screen.getByText('Network')).toBeInTheDocument();
  });

  it('should display CPU usage percentage', () => {
    render(<MetricsDisplay metrics={mockMetrics} />);

    expect(screen.getByText('45.5%')).toBeInTheDocument();
    expect(screen.getByText('8 cores')).toBeInTheDocument();
  });

  it('should display memory usage', () => {
    render(<MetricsDisplay metrics={mockMetrics} />);

    expect(screen.getByText('50.0%')).toBeInTheDocument();
    expect(screen.getByText(/8 GB \/ 16 GB/)).toBeInTheDocument();
  });

  it('should display disk usage', () => {
    render(<MetricsDisplay metrics={mockMetrics} />);

    expect(screen.getByText('40.0%')).toBeInTheDocument();
    expect(screen.getByText(/300 GB available/)).toBeInTheDocument();
  });

  it('should display network transfer', () => {
    render(<MetricsDisplay metrics={mockMetrics} />);

    expect(screen.getByText(/5 MB/)).toBeInTheDocument();
    expect(screen.getByText(/2 MB/)).toBeInTheDocument();
  });

  it('should render metric bars with correct width', () => {
    const { container } = render(<MetricsDisplay metrics={mockMetrics} />);

    const bars = container.querySelectorAll('.metric-bar-fill');

    // CPU bar should be 45.5% width
    expect(bars[0]).toHaveStyle({ width: '45.5%' });

    // Memory bar should be 50% width
    expect(bars[1]).toHaveStyle({ width: '50%' });

    // Disk bar should be 40% width
    expect(bars[2]).toHaveStyle({ width: '40%' });
  });

  it('should apply correct color for low metric values', () => {
    const { container } = render(<MetricsDisplay metrics={mockMetrics} />);

    const bars = container.querySelectorAll('.metric-bar-fill');

    // All bars should be green (low usage)
    bars.forEach((bar) => {
      expect(bar).toHaveStyle({ backgroundColor: '#10b981' });
    });
  });

  it('should apply warning color for medium metric values', () => {
    const warningMetrics: MoleStatusMetrics = {
      ...mockMetrics,
      cpu: { usage: 75, cores: 8 },
      memory: { ...mockMetrics.memory, percentage: 70 },
      disk: { ...mockMetrics.disk, percentage: 85 },
    };

    const { container } = render(<MetricsDisplay metrics={warningMetrics} />);

    const bars = container.querySelectorAll('.metric-bar-fill');

    // CPU and Memory should be yellow (warning)
    expect(bars[0]).toHaveStyle({ backgroundColor: '#f59e0b' });
    expect(bars[1]).toHaveStyle({ backgroundColor: '#f59e0b' });
    expect(bars[2]).toHaveStyle({ backgroundColor: '#f59e0b' });
  });

  it('should apply critical color for high metric values', () => {
    const criticalMetrics: MoleStatusMetrics = {
      ...mockMetrics,
      cpu: { usage: 95, cores: 8 },
      memory: { ...mockMetrics.memory, percentage: 90 },
      disk: { ...mockMetrics.disk, percentage: 95 },
    };

    const { container } = render(<MetricsDisplay metrics={criticalMetrics} />);

    const bars = container.querySelectorAll('.metric-bar-fill');

    // All bars should be red (critical)
    expect(bars[0]).toHaveStyle({ backgroundColor: '#ef4444' });
    expect(bars[1]).toHaveStyle({ backgroundColor: '#ef4444' });
    expect(bars[2]).toHaveStyle({ backgroundColor: '#ef4444' });
  });
});
