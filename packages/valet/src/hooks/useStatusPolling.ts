import { useState, useEffect, useCallback } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import { getSystemStatus } from '../lib/mole';
import { MoleStatusMetrics } from '../lib/moleTypes';

/**
 * Poll interval in milliseconds (5 seconds for fallback)
 */
const POLL_INTERVAL = 5000;

export interface MonitoringStatus {
  health: string;
  last_update: string;
  status_json: any;
}

export interface UseStatusPollingResult {
  metrics: MoleStatusMetrics | null;
  loading: boolean;
  error: string | null;
  offline: boolean;
  lastUpdate: string | null;
  refetch: () => Promise<void>;
}

/**
 * Hook to consume monitoring events from the background monitoring loop
 * and provide cached status with offline state detection.
 * Falls back to polling if events are not available.
 */
export function useStatusPolling(): UseStatusPollingResult {
  const [metrics, setMetrics] = useState<MoleStatusMetrics | null>(null);
  const [loading, setLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);
  const [offline, setOffline] = useState<boolean>(false);
  const [lastUpdate, setLastUpdate] = useState<string | null>(null);

  // Fetch cached status from monitoring
  const fetchCachedStatus = useCallback(async () => {
    try {
      const cached = await invoke<MonitoringStatus | null>('get_cached_status');
      if (cached) {
        setMetrics(cached.status_json);
        setLastUpdate(cached.last_update);
        setOffline(false);
        setError(null);
      } else {
        // No cached status, try fetching directly
        await fetchStatus();
      }
    } catch (err) {
      console.error('Failed to fetch cached status:', err);
      // Fall back to direct fetch
      await fetchStatus();
    } finally {
      setLoading(false);
    }
  }, []);

  const fetchStatus = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const status = await getSystemStatus();
      setMetrics(status);
      setOffline(false);
      setLastUpdate(new Date().toISOString());
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to fetch system status';
      setError(errorMessage);
      setOffline(true);
      console.error('Status polling error:', err);
    } finally {
      setLoading(false);
    }
  }, []);

  // Initial fetch on mount - try cached first
  useEffect(() => {
    fetchCachedStatus();
  }, [fetchCachedStatus]);

  // Listen to monitoring events
  useEffect(() => {
    const unsubscribe = listen<MonitoringStatus>('monitoring:status', (event) => {
      const status = event.payload;
      setMetrics(status.status_json);
      setLastUpdate(status.last_update);
      setOffline(false);
      setError(null);
      setLoading(false);
    });

    const unsubscribeError = listen<string>('monitoring:error', (event) => {
      setError(event.payload);
      setOffline(true);
    });

    return () => {
      unsubscribe.then((fn) => fn());
      unsubscribeError.then((fn) => fn());
    };
  }, []);

  // Set up polling interval (every 5 seconds)
  // Always fetch fresh status, not just cached data
  useEffect(() => {
    const intervalId = setInterval(() => {
      fetchStatus();
    }, POLL_INTERVAL);

    // Cleanup on unmount
    return () => {
      clearInterval(intervalId);
    };
  }, [fetchStatus]);

  return {
    metrics,
    loading,
    error,
    offline,
    lastUpdate,
    refetch: fetchStatus,
  };
}
