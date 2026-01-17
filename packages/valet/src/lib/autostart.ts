import { invoke } from '@tauri-apps/api/core';

/**
 * Enable or disable auto-launch on system startup.
 * When enabled, the app will launch minimized to the menubar on system startup.
 *
 * @param enable - Whether to enable auto-launch
 * @throws Error if the operation fails
 */
export async function setAutostart(enable: boolean): Promise<void> {
  await invoke('set_autostart', { enable });
}

/**
 * Check if auto-launch is currently enabled.
 *
 * @returns True if auto-launch is enabled, false otherwise
 * @throws Error if the operation fails
 */
export async function isAutostartEnabled(): Promise<boolean> {
  return await invoke('is_autostart_enabled');
}
