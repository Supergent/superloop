/**
 * React hook for Mole CLI operations
 * Provides loading/error state management for all Mole commands
 */

import { useState, useCallback } from 'react';
import type {
  MoleStatusMetrics,
  MoleAnalyzeResult,
  MoleCleanResult,
  MoleUninstallResult,
  MoleOptimizeResult,
  MolePurgeResult,
  MoleInstallerResult,
  MoleError,
} from '../lib/moleTypes';
import {
  getSystemStatus,
  analyzeDiskUsage,
  cleanSystem,
  uninstallApp,
  optimizeSystem,
  purgeDeveloperArtifacts,
  cleanupInstallers,
} from '../lib/mole';

// ============================================================================
// Types
// ============================================================================

interface UseMoleState<T> {
  data: T | null;
  loading: boolean;
  error: MoleError | null;
}

interface UseMoleActions {
  // System status
  getStatus: () => Promise<MoleStatusMetrics | null>;

  // Disk analysis
  analyze: (path?: string) => Promise<MoleAnalyzeResult | null>;

  // Cleanup operations
  clean: (options?: { dryRun?: boolean }) => Promise<MoleCleanResult | null>;
  uninstall: (appName: string) => Promise<MoleUninstallResult | null>;
  optimize: (options?: { dryRun?: boolean }) => Promise<MoleOptimizeResult | null>;
  purge: (options?: { dryRun?: boolean }) => Promise<MolePurgeResult | null>;
  cleanInstallers: (options?: { dryRun?: boolean }) => Promise<MoleInstallerResult | null>;

  // Reset state
  reset: () => void;
}

interface UseMoleResult {
  status: UseMoleState<MoleStatusMetrics>;
  analyze: UseMoleState<MoleAnalyzeResult>;
  clean: UseMoleState<MoleCleanResult>;
  uninstall: UseMoleState<MoleUninstallResult>;
  optimize: UseMoleState<MoleOptimizeResult>;
  purge: UseMoleState<MolePurgeResult>;
  installers: UseMoleState<MoleInstallerResult>;
  actions: UseMoleActions;
}

// ============================================================================
// Hook
// ============================================================================

export function useMole(): UseMoleResult {
  // State for each command type
  const [statusState, setStatusState] = useState<UseMoleState<MoleStatusMetrics>>({
    data: null,
    loading: false,
    error: null,
  });

  const [analyzeState, setAnalyzeState] = useState<UseMoleState<MoleAnalyzeResult>>({
    data: null,
    loading: false,
    error: null,
  });

  const [cleanState, setCleanState] = useState<UseMoleState<MoleCleanResult>>({
    data: null,
    loading: false,
    error: null,
  });

  const [uninstallState, setUninstallState] = useState<UseMoleState<MoleUninstallResult>>({
    data: null,
    loading: false,
    error: null,
  });

  const [optimizeState, setOptimizeState] = useState<UseMoleState<MoleOptimizeResult>>({
    data: null,
    loading: false,
    error: null,
  });

  const [purgeState, setPurgeState] = useState<UseMoleState<MolePurgeResult>>({
    data: null,
    loading: false,
    error: null,
  });

  const [installersState, setInstallersState] = useState<UseMoleState<MoleInstallerResult>>({
    data: null,
    loading: false,
    error: null,
  });

  // ============================================================================
  // Actions
  // ============================================================================

  const getStatus = useCallback(async () => {
    setStatusState({ data: null, loading: true, error: null });
    try {
      const data = await getSystemStatus();
      setStatusState({ data, loading: false, error: null });
      return data;
    } catch (error) {
      const moleError = error as MoleError;
      setStatusState({ data: null, loading: false, error: moleError });
      return null;
    }
  }, []);

  const analyze = useCallback(async (path?: string) => {
    setAnalyzeState({ data: null, loading: true, error: null });
    try {
      const data = await analyzeDiskUsage(path);
      setAnalyzeState({ data, loading: false, error: null });
      return data;
    } catch (error) {
      const moleError = error as MoleError;
      setAnalyzeState({ data: null, loading: false, error: moleError });
      return null;
    }
  }, []);

  const clean = useCallback(async (options?: { dryRun?: boolean }) => {
    setCleanState({ data: null, loading: true, error: null });
    try {
      const data = await cleanSystem(options);
      setCleanState({ data, loading: false, error: null });
      return data;
    } catch (error) {
      const moleError = error as MoleError;
      setCleanState({ data: null, loading: false, error: moleError });
      return null;
    }
  }, []);

  const uninstall = useCallback(async (appName: string) => {
    setUninstallState({ data: null, loading: true, error: null });
    try {
      const data = await uninstallApp(appName);
      setUninstallState({ data, loading: false, error: null });
      return data;
    } catch (error) {
      const moleError = error as MoleError;
      setUninstallState({ data: null, loading: false, error: moleError });
      return null;
    }
  }, []);

  const optimize = useCallback(async (options?: { dryRun?: boolean }) => {
    setOptimizeState({ data: null, loading: true, error: null });
    try {
      const data = await optimizeSystem(options);
      setOptimizeState({ data, loading: false, error: null });
      return data;
    } catch (error) {
      const moleError = error as MoleError;
      setOptimizeState({ data: null, loading: false, error: moleError });
      return null;
    }
  }, []);

  const purge = useCallback(async (options?: { dryRun?: boolean }) => {
    setPurgeState({ data: null, loading: true, error: null });
    try {
      const data = await purgeDeveloperArtifacts(options);
      setPurgeState({ data, loading: false, error: null });
      return data;
    } catch (error) {
      const moleError = error as MoleError;
      setPurgeState({ data: null, loading: false, error: moleError });
      return null;
    }
  }, []);

  const cleanInstallers = useCallback(async (options?: { dryRun?: boolean }) => {
    setInstallersState({ data: null, loading: true, error: null });
    try {
      const data = await cleanupInstallers(options);
      setInstallersState({ data, loading: false, error: null });
      return data;
    } catch (error) {
      const moleError = error as MoleError;
      setInstallersState({ data: null, loading: false, error: moleError });
      return null;
    }
  }, []);

  const reset = useCallback(() => {
    setStatusState({ data: null, loading: false, error: null });
    setAnalyzeState({ data: null, loading: false, error: null });
    setCleanState({ data: null, loading: false, error: null });
    setUninstallState({ data: null, loading: false, error: null });
    setOptimizeState({ data: null, loading: false, error: null });
    setPurgeState({ data: null, loading: false, error: null });
    setInstallersState({ data: null, loading: false, error: null });
  }, []);

  // ============================================================================
  // Return
  // ============================================================================

  return {
    status: statusState,
    analyze: analyzeState,
    clean: cleanState,
    uninstall: uninstallState,
    optimize: optimizeState,
    purge: purgeState,
    installers: installersState,
    actions: {
      getStatus,
      analyze,
      clean,
      uninstall,
      optimize,
      purge,
      cleanInstallers,
      reset,
    },
  };
}

export default useMole;
