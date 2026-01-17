import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { useStatusPolling } from '../useStatusPolling';
import { mockInvoke, mockListen, mockEmit } from '../../test/setup';

// Mock the mole module
vi.mock('../../lib/mole', () => ({
  getSystemStatus: vi.fn(async () => ({
    cpu: { usage: 45.5 },
    memory: { used: 8589934592, total: 17179869184 },
    disk: { used: 500000000000, total: 1000000000000 },
    network: { upload: 1024, download: 2048 },
  })),
}));

describe('useStatusPolling', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('should fetch cached status on mount', async () => {
    const mockStatus = {
      health: 'good',
      last_update: '2024-01-16T12:00:00Z',
      status_json: {
        cpu: { usage: 30.0 },
        memory: { used: 4294967296, total: 17179869184 },
        disk: { used: 400000000000, total: 1000000000000 },
        network: { upload: 512, download: 1024 },
      },
    };

    mockInvoke.mockImplementation(async (cmd: string) => {
      if (cmd === 'get_cached_status') {
        return mockStatus;
      }
      return null;
    });

    const { result } = renderHook(() => useStatusPolling());

    // Initially loading
    expect(result.current.loading).toBe(true);

    // Wait for the data to load
    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    // Check that metrics are set correctly
    expect(result.current.metrics).toEqual(mockStatus.status_json);
    expect(result.current.lastUpdate).toBe(mockStatus.last_update);
    expect(result.current.offline).toBe(false);
    expect(result.current.error).toBe(null);
  });

  it('should handle monitoring:status events', async () => {
    let statusHandler: ((event: any) => void) | null = null;

    // Mock listen to capture the handler
    mockListen.mockImplementation(async (event: string, handler: (event: any) => void) => {
      if (event === 'monitoring:status') {
        statusHandler = handler;
      }
      return () => {}; // Return unlisten function
    });

    const { result } = renderHook(() => useStatusPolling());

    // Wait for initial load
    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    // Simulate a monitoring event
    const newStatus = {
      health: 'warning',
      last_update: '2024-01-16T13:00:00Z',
      status_json: {
        cpu: { usage: 75.0 },
        memory: { used: 12884901888, total: 17179869184 },
        disk: { used: 900000000000, total: 1000000000000 },
        network: { upload: 2048, download: 4096 },
      },
    };

    if (statusHandler) {
      statusHandler({ payload: newStatus });
    }

    // Check that metrics are updated
    await waitFor(() => {
      expect(result.current.metrics).toEqual(newStatus.status_json);
      expect(result.current.lastUpdate).toBe(newStatus.last_update);
      expect(result.current.offline).toBe(false);
    });
  });

  it('should handle monitoring:error events', async () => {
    let errorHandler: ((event: any) => void) | null = null;

    // Mock listen to capture the error handler
    mockListen.mockImplementation(async (event: string, handler: (event: any) => void) => {
      if (event === 'monitoring:error') {
        errorHandler = handler;
      }
      return () => {}; // Return unlisten function
    });

    const { result } = renderHook(() => useStatusPolling());

    // Wait for initial load
    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    // Simulate an error event
    const errorMessage = 'Failed to fetch status';
    if (errorHandler) {
      errorHandler({ payload: errorMessage });
    }

    // Check that error state is set
    await waitFor(() => {
      expect(result.current.error).toBe(errorMessage);
      expect(result.current.offline).toBe(true);
    });
  });

  it('should fall back to direct fetch when no cached status', async () => {
    mockInvoke.mockImplementation(async (cmd: string) => {
      if (cmd === 'get_cached_status') {
        return null; // No cached status
      }
      return null;
    });

    const { result } = renderHook(() => useStatusPolling());

    // Wait for the data to load
    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    // Should have metrics from getSystemStatus mock
    expect(result.current.metrics).toBeTruthy();
    expect(result.current.metrics?.cpu).toBeDefined();
    expect(result.current.offline).toBe(false);
  });

  it('should set offline state when fetch fails', async () => {
    const { getSystemStatus } = await import('../../lib/mole');

    // Mock getSystemStatus to throw an error
    vi.mocked(getSystemStatus).mockRejectedValueOnce(new Error('Network error'));

    mockInvoke.mockImplementation(async (cmd: string) => {
      if (cmd === 'get_cached_status') {
        return null; // No cached status
      }
      return null;
    });

    const { result } = renderHook(() => useStatusPolling());

    // Wait for the error to be handled
    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    // Should be in offline state
    expect(result.current.offline).toBe(true);
    expect(result.current.error).toBeTruthy();
  });

  it('should expose refetch function', async () => {
    const { result } = renderHook(() => useStatusPolling());

    // Wait for initial load
    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    // Refetch should be a function
    expect(typeof result.current.refetch).toBe('function');

    // Call refetch
    await result.current.refetch();

    // Should still have metrics
    expect(result.current.metrics).toBeTruthy();
  });

  it('should poll every 5 seconds for fresh status (not cached)', async () => {
    vi.useFakeTimers();

    const { getSystemStatus } = await import('../../lib/mole');

    let callCount = 0;
    vi.mocked(getSystemStatus).mockImplementation(async () => {
      callCount++;
      return {
        cpu: { usage: 30.0 },
        memory: { used: 4294967296, total: 17179869184 },
        disk: { used: 400000000000, total: 1000000000000 },
        network: { upload: 512, download: 1024 },
      };
    });

    // Mock get_cached_status to return null so it falls back to direct fetch
    mockInvoke.mockResolvedValue(null);

    renderHook(() => useStatusPolling());

    // Wait for initial mount call
    await vi.waitFor(() => {
      expect(callCount).toBe(1);
    });

    // Advance time by 5 seconds - should trigger fresh fetch
    vi.advanceTimersByTime(5000);

    await vi.waitFor(() => {
      expect(callCount).toBe(2);
    });

    // Advance time by another 5 seconds
    vi.advanceTimersByTime(5000);

    await vi.waitFor(() => {
      expect(callCount).toBe(3);
    });

    // Advance time by another 5 seconds
    vi.advanceTimersByTime(5000);

    await vi.waitFor(() => {
      expect(callCount).toBe(4);
    });

    vi.useRealTimers();
  });

  it('should fetch fresh status every 5s even when cached data exists', async () => {
    vi.useFakeTimers();

    const { getSystemStatus } = await import('../../lib/mole');

    const mockCachedStatus = {
      health: 'good',
      last_update: new Date().toISOString(), // Recent cached data
      status_json: {
        cpu: { usage: 30.0 },
        memory: { used: 4294967296, total: 17179869184 },
        disk: { used: 400000000000, total: 1000000000000 },
        network: { upload: 512, download: 1024 },
      },
    };

    // Mock cached status to return data (simulating that cached data exists)
    mockInvoke.mockResolvedValue(mockCachedStatus);

    let freshFetchCount = 0;
    vi.mocked(getSystemStatus).mockImplementation(async () => {
      freshFetchCount++;
      return {
        cpu: { usage: 40.0 + freshFetchCount },
        memory: { used: 5000000000 + freshFetchCount * 1000000, total: 17179869184 },
        disk: { used: 400000000000, total: 1000000000000 },
        network: { upload: 512, download: 1024 },
      };
    });

    renderHook(() => useStatusPolling());

    // Wait for initial mount call (fetchCachedStatus on mount)
    await vi.waitFor(() => {
      expect(mockInvoke).toHaveBeenCalled();
    });

    // Initial fresh fetch count should be 0 (only cached status was fetched)
    expect(freshFetchCount).toBe(0);

    // Advance time by 5 seconds - should trigger FRESH fetch via fetchStatus()
    vi.advanceTimersByTime(5000);

    await vi.waitFor(() => {
      expect(freshFetchCount).toBe(1);
    });

    // Advance time by another 5 seconds - should trigger another fresh fetch
    vi.advanceTimersByTime(5000);

    await vi.waitFor(() => {
      expect(freshFetchCount).toBe(2);
    });

    // Verify it continues to fetch fresh data regardless of cached data existing
    vi.advanceTimersByTime(5000);

    await vi.waitFor(() => {
      expect(freshFetchCount).toBe(3);
    });

    vi.useRealTimers();
  });
});
