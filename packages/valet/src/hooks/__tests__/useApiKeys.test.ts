import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { useApiKeys } from '../useApiKeys';
import { mockInvoke, mockKeychain } from '../../test/setup';

describe('useApiKeys', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    Object.keys(mockKeychain).forEach(key => delete mockKeychain[key]);
  });

  it('should not load keys on mount when enabled is false (default)', async () => {
    const { result } = renderHook(() => useApiKeys());

    // Should not be loading since enabled is false by default
    expect(result.current.loading).toBe(false);

    // Keys should be null
    expect(result.current.keys.assemblyAi).toBe(null);
    expect(result.current.keys.vapiPublic).toBe(null);
    expect(result.current.keys.llmProxy).toBe(null);

    // Verify no keychain commands were called
    expect(mockInvoke).not.toHaveBeenCalledWith(
      'get_key_command',
      expect.anything()
    );
  });

  it('should load keys on mount when enabled is true', async () => {
    // Pre-populate keychain
    mockKeychain['assemblyai'] = 'test-assembly-key';
    mockKeychain['vapi-public'] = 'test-vapi-key';
    mockKeychain['llm-proxy'] = 'test-llm-key';

    const { result } = renderHook(() => useApiKeys({ enabled: true }));

    // Initially loading
    expect(result.current.loading).toBe(true);

    // Wait for keys to load
    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    // Check that keys are loaded
    expect(result.current.keys.assemblyAi).toBe('test-assembly-key');
    expect(result.current.keys.vapiPublic).toBe('test-vapi-key');
    expect(result.current.keys.llmProxy).toBe('test-llm-key');

    // Check status
    expect(result.current.status.assemblyAi).toBe(true);
    expect(result.current.status.vapiPublic).toBe(true);
    expect(result.current.status.llmProxy).toBe(true);
  });

  it('should load keys when enabled changes from false to true', async () => {
    // Pre-populate keychain
    mockKeychain['assemblyai'] = 'test-assembly-key';

    const { result, rerender } = renderHook(
      ({ enabled }) => useApiKeys({ enabled }),
      { initialProps: { enabled: false } }
    );

    // Should not be loading initially
    expect(result.current.loading).toBe(false);
    expect(result.current.keys.assemblyAi).toBe(null);

    // Change enabled to true
    rerender({ enabled: true });

    // Should start loading
    await waitFor(() => {
      expect(result.current.loading).toBe(true);
    });

    // Wait for keys to load
    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    // Check that keys are loaded
    expect(result.current.keys.assemblyAi).toBe('test-assembly-key');
  });

  it('should save a key to keychain', async () => {
    const { result } = renderHook(() => useApiKeys({ enabled: true }));

    // Wait for initial load
    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    // Save a key
    await result.current.saveKey('assemblyai', 'new-assembly-key');

    // Wait for save to complete
    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    // Check that key is saved
    expect(mockKeychain['assemblyai']).toBe('new-assembly-key');
    expect(result.current.keys.assemblyAi).toBe('new-assembly-key');
    expect(result.current.status.assemblyAi).toBe(true);
  });

  it('should delete a key from keychain', async () => {
    // Pre-populate keychain
    mockKeychain['assemblyai'] = 'test-assembly-key';

    const { result } = renderHook(() => useApiKeys({ enabled: true }));

    // Wait for initial load
    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    // Verify key is loaded
    expect(result.current.keys.assemblyAi).toBe('test-assembly-key');

    // Delete the key
    await result.current.removeKey('assemblyai');

    // Wait for deletion to complete
    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    // Check that key is deleted
    expect(mockKeychain['assemblyai']).toBeUndefined();
    expect(result.current.keys.assemblyAi).toBe(null);
    expect(result.current.status.assemblyAi).toBe(false);
  });

  it('should handle errors when loading keys fails', async () => {
    // Mock invoke to throw error
    mockInvoke.mockRejectedValueOnce(new Error('Keychain access denied'));

    const { result } = renderHook(() => useApiKeys({ enabled: true }));

    // Wait for error to be set
    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    // Check error state
    expect(result.current.error).toContain('Keychain access denied');
  });

  it('should handle errors when saving a key fails', async () => {
    const { result } = renderHook(() => useApiKeys({ enabled: true }));

    // Wait for initial load
    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    // Mock invoke to throw error on save
    mockInvoke.mockRejectedValueOnce(new Error('Keychain write failed'));

    // Try to save a key
    await expect(
      result.current.saveKey('assemblyai', 'new-key')
    ).rejects.toThrow('Keychain write failed');

    // Check error state
    await waitFor(() => {
      expect(result.current.error).toContain('Keychain write failed');
    });
  });

  it('should expose loadKeys and refreshStatus functions', async () => {
    const { result } = renderHook(() => useApiKeys({ enabled: false }));

    // Functions should be available
    expect(typeof result.current.loadKeys).toBe('function');
    expect(typeof result.current.refreshStatus).toBe('function');

    // Pre-populate keychain
    mockKeychain['assemblyai'] = 'test-key';

    // Manually call loadKeys
    await result.current.loadKeys();

    // Wait for keys to load
    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    // Check that keys are loaded
    expect(result.current.keys.assemblyAi).toBe('test-key');
  });
});
