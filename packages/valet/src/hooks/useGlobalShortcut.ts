import { useEffect, useCallback, useRef } from 'react';
import { register, unregister, isRegistered } from '@tauri-apps/plugin-global-shortcut';

export interface GlobalShortcutOptions {
  /** The keyboard shortcut (e.g., 'CommandOrControl+Shift+Space') */
  shortcut: string;
  /** Callback when the shortcut is triggered */
  onTrigger: () => void;
  /** Whether the shortcut is enabled (default: true) */
  enabled?: boolean;
}

/**
 * Hook for registering global keyboard shortcuts.
 *
 * @param options - Shortcut configuration
 * @returns Object with registration status and utility functions
 */
export function useGlobalShortcut({
  shortcut,
  onTrigger,
  enabled = true,
}: GlobalShortcutOptions) {
  const callbackRef = useRef(onTrigger);
  const shortcutRef = useRef(shortcut);

  // Keep callback ref up to date
  useEffect(() => {
    callbackRef.current = onTrigger;
  }, [onTrigger]);

  // Keep shortcut ref up to date
  useEffect(() => {
    shortcutRef.current = shortcut;
  }, [shortcut]);

  const registerShortcut = useCallback(async () => {
    try {
      // Check if already registered
      const registered = await isRegistered(shortcutRef.current);
      if (registered) {
        console.log(`Shortcut ${shortcutRef.current} already registered`);
        return;
      }

      // Register the shortcut
      await register(shortcutRef.current, () => {
        callbackRef.current();
      });

      console.log(`Registered global shortcut: ${shortcutRef.current}`);
    } catch (error) {
      console.error(`Failed to register shortcut ${shortcutRef.current}:`, error);
    }
  }, []);

  const unregisterShortcut = useCallback(async () => {
    try {
      await unregister(shortcutRef.current);
      console.log(`Unregistered global shortcut: ${shortcutRef.current}`);
    } catch (error) {
      console.error(`Failed to unregister shortcut ${shortcutRef.current}:`, error);
    }
  }, []);

  // Register/unregister based on enabled state
  useEffect(() => {
    if (enabled) {
      registerShortcut();
    } else {
      unregisterShortcut();
    }

    // Cleanup on unmount
    return () => {
      unregisterShortcut();
    };
  }, [enabled, registerShortcut, unregisterShortcut]);

  return {
    register: registerShortcut,
    unregister: unregisterShortcut,
  };
}
