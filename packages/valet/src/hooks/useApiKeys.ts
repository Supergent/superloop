import { useState, useEffect, useCallback, useRef } from 'react';
import { storeKey, getKey, deleteKey, getAllKeys, getKeyStatus, KEY_NAMES, type KeyName } from '../lib/keys';

export interface ApiKeys {
  assemblyAi: string | null;
  vapiPublic: string | null;
  llmProxy: string | null;
}

export interface ApiKeysStatus {
  assemblyAi: boolean;
  vapiPublic: boolean;
  llmProxy: boolean;
}

export interface UseApiKeysOptions {
  enabled?: boolean;
}

export interface UseApiKeysResult {
  keys: ApiKeys;
  status: ApiKeysStatus;
  loading: boolean;
  error: string | null;
  loadKeys: () => Promise<void>;
  saveKey: (keyName: KeyName, keyValue: string) => Promise<void>;
  removeKey: (keyName: KeyName) => Promise<void>;
  refreshStatus: () => Promise<void>;
}

/**
 * Hook for managing API keys stored in macOS Keychain
 * Provides load, store, and delete operations for AssemblyAI, Vapi, and llm-proxy keys
 * @param options.enabled - Whether to load keys automatically. Defaults to false to avoid unnecessary keychain access.
 */
export function useApiKeys(options: UseApiKeysOptions = {}): UseApiKeysResult {
  const { enabled = false } = options;
  const [keys, setKeys] = useState<ApiKeys>({
    assemblyAi: null,
    vapiPublic: null,
    llmProxy: null,
  });

  const [status, setStatus] = useState<ApiKeysStatus>({
    assemblyAi: false,
    vapiPublic: false,
    llmProxy: false,
  });

  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Track active operations to prevent race conditions
  const activeOperations = useRef(0);

  /**
   * Load all API keys from Keychain
   */
  const loadKeys = useCallback(async () => {
    activeOperations.current++;
    if (activeOperations.current === 1) {
      setLoading(true);
    }
    setError(null);
    try {
      const allKeys = await getAllKeys();
      setKeys(allKeys);
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to load API keys';
      setError(message);
      console.error('Error loading API keys:', err);
    } finally {
      activeOperations.current--;
      if (activeOperations.current === 0) {
        setLoading(false);
      }
    }
  }, []);

  /**
   * Refresh the status of which keys are configured
   */
  const refreshStatus = useCallback(async () => {
    activeOperations.current++;
    if (activeOperations.current === 1) {
      setLoading(true);
    }
    setError(null);
    try {
      const keyStatus = await getKeyStatus();
      setStatus(keyStatus);
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to check API key status';
      setError(message);
      console.error('Error checking API key status:', err);
    } finally {
      activeOperations.current--;
      if (activeOperations.current === 0) {
        setLoading(false);
      }
    }
  }, []);

  /**
   * Save a single API key to Keychain
   */
  const saveKey = useCallback(async (keyName: KeyName, keyValue: string) => {
    setLoading(true);
    setError(null);
    try {
      await storeKey(keyName, keyValue);
      // Directly update keys and status after saving
      const [allKeys, keyStatus] = await Promise.all([getAllKeys(), getKeyStatus()]);
      setKeys(allKeys);
      setStatus(keyStatus);
    } catch (err) {
      const message = err instanceof Error ? err.message : `Failed to save ${keyName}`;
      setError(message);
      console.error(`Error saving key ${keyName}:`, err);
      throw err; // Re-throw so caller can handle
    } finally {
      setLoading(false);
    }
  }, []);

  /**
   * Delete a single API key from Keychain
   */
  const removeKey = useCallback(async (keyName: KeyName) => {
    setLoading(true);
    setError(null);
    try {
      await deleteKey(keyName);
      // Directly update keys and status after deleting
      const [allKeys, keyStatus] = await Promise.all([getAllKeys(), getKeyStatus()]);
      setKeys(allKeys);
      setStatus(keyStatus);
    } catch (err) {
      const message = err instanceof Error ? err.message : `Failed to delete ${keyName}`;
      setError(message);
      console.error(`Error deleting key ${keyName}:`, err);
      throw err; // Re-throw so caller can handle
    } finally {
      setLoading(false);
    }
  }, []);

  // Load keys and status on mount, but only if enabled
  useEffect(() => {
    if (enabled) {
      loadKeys();
      refreshStatus();
    }
  }, [enabled, loadKeys, refreshStatus]);

  return {
    keys,
    status,
    loading,
    error,
    loadKeys,
    saveKey,
    removeKey,
    refreshStatus,
  };
}
