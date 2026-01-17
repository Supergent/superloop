import { useState, useEffect, useCallback } from 'react';
import { isAutostartEnabled, setAutostart } from '../lib/autostart';

/**
 * React hook for managing auto-launch on system startup.
 *
 * @returns Object containing enabled state, loading state, error state, and toggle function
 *
 * @example
 * ```tsx
 * function Settings() {
 *   const { enabled, loading, error, toggle } = useAutostart();
 *
 *   return (
 *     <div>
 *       <label>
 *         <input
 *           type="checkbox"
 *           checked={enabled}
 *           disabled={loading}
 *           onChange={(e) => toggle(e.target.checked)}
 *         />
 *         Launch at startup
 *       </label>
 *       {error && <p>Error: {error}</p>}
 *     </div>
 *   );
 * }
 * ```
 */
export function useAutostart() {
  const [enabled, setEnabled] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Load initial state
  useEffect(() => {
    async function loadAutostart() {
      try {
        setLoading(true);
        const isEnabled = await isAutostartEnabled();
        setEnabled(isEnabled);
        setError(null);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Failed to check autostart status');
      } finally {
        setLoading(false);
      }
    }

    loadAutostart();
  }, []);

  // Toggle function
  const toggle = useCallback(async (enable: boolean) => {
    try {
      setLoading(true);
      setError(null);
      await setAutostart(enable);
      setEnabled(enable);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to update autostart setting');
      // Revert on error
      try {
        const currentState = await isAutostartEnabled();
        setEnabled(currentState);
      } catch {
        // Ignore error on revert check
      }
    } finally {
      setLoading(false);
    }
  }, []);

  return {
    enabled,
    loading,
    error,
    toggle,
  };
}
