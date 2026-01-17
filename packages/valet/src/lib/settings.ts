import { useState, useEffect } from 'react';
import { invoke } from '@tauri-apps/api/core';

export interface Settings {
  voiceEnabled: string;
  monitoringFrequency: string;
  notificationMode: string;
  autoStart: string;
  diskWarningThreshold: string;  // GB, default 20
  diskCriticalThreshold: string; // GB, default 10
  [key: string]: string;
}

/**
 * Get a single setting value
 */
export async function getSetting(key: string): Promise<string | null> {
  try {
    const value = await invoke<string | null>('get_setting_command', { key });
    return value;
  } catch (error) {
    console.error(`Failed to get setting ${key}:`, error);
    return null;
  }
}

/**
 * Set a single setting value
 */
export async function setSetting(key: string, value: string): Promise<void> {
  try {
    await invoke('set_setting_command', { key, value });
  } catch (error) {
    console.error(`Failed to set setting ${key}:`, error);
    throw error;
  }
}

/**
 * Delete a setting
 */
export async function deleteSetting(key: string): Promise<void> {
  try {
    await invoke('delete_setting_command', { key });
  } catch (error) {
    console.error(`Failed to delete setting ${key}:`, error);
    throw error;
  }
}

/**
 * Get all settings
 */
/**
 * Default alert thresholds (in GB)
 */
export const DEFAULT_DISK_WARNING_THRESHOLD = 20;
export const DEFAULT_DISK_CRITICAL_THRESHOLD = 10;

export async function getAllSettings(): Promise<Settings> {
  try {
    const settings = await invoke<Record<string, string>>('get_all_settings_command');

    // Sanitize disk threshold settings - fallback to defaults when invalid
    const warningThreshold = parseFloat(settings.diskWarningThreshold || '');
    const criticalThreshold = parseFloat(settings.diskCriticalThreshold || '');

    const sanitizedWarningThreshold =
      !isNaN(warningThreshold) && warningThreshold > 0
        ? warningThreshold.toString()
        : DEFAULT_DISK_WARNING_THRESHOLD.toString();

    const sanitizedCriticalThreshold =
      !isNaN(criticalThreshold) && criticalThreshold > 0
        ? criticalThreshold.toString()
        : DEFAULT_DISK_CRITICAL_THRESHOLD.toString();

    return {
      ...settings,
      voiceEnabled: settings.voiceEnabled || 'true',
      monitoringFrequency: settings.monitoringFrequency || '30',
      notificationMode: settings.notificationMode || 'critical',
      autoStart: settings.autoStart || 'false',
      diskWarningThreshold: sanitizedWarningThreshold,
      diskCriticalThreshold: sanitizedCriticalThreshold,
    };
  } catch (error) {
    console.error('Failed to get all settings:', error);
    return {
      voiceEnabled: 'true',
      monitoringFrequency: '30',
      notificationMode: 'critical',
      autoStart: 'false',
      diskWarningThreshold: DEFAULT_DISK_WARNING_THRESHOLD.toString(),
      diskCriticalThreshold: DEFAULT_DISK_CRITICAL_THRESHOLD.toString(),
    };
  }
}

/**
 * React hook for managing settings
 */
export function useSettings() {
  const [settings, setSettings] = useState<Settings>({
    voiceEnabled: 'true',
    monitoringFrequency: '30',
    notificationMode: 'critical',
    autoStart: 'false',
    diskWarningThreshold: DEFAULT_DISK_WARNING_THRESHOLD.toString(),
    diskCriticalThreshold: DEFAULT_DISK_CRITICAL_THRESHOLD.toString(),
  });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Load all settings on mount
  useEffect(() => {
    const loadSettings = async () => {
      setLoading(true);
      setError(null);
      try {
        const allSettings = await getAllSettings();
        setSettings(allSettings);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Failed to load settings');
      } finally {
        setLoading(false);
      }
    };

    loadSettings();
  }, []);

  // Update a single setting
  const updateSetting = async (key: string, value: string) => {
    try {
      await setSetting(key, value);
      setSettings((prev) => ({ ...prev, [key]: value }));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to update setting');
      throw err;
    }
  };

  // Delete a setting
  const removeSetting = async (key: string) => {
    try {
      await deleteSetting(key);
      setSettings((prev) => {
        const newSettings = { ...prev };
        delete newSettings[key];
        return newSettings;
      });
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to delete setting');
      throw err;
    }
  };

  // Refresh all settings
  const refresh = async () => {
    setLoading(true);
    setError(null);
    try {
      const allSettings = await getAllSettings();
      setSettings(allSettings);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to refresh settings');
    } finally {
      setLoading(false);
    }
  };

  return {
    settings,
    loading,
    error,
    updateSetting,
    removeSetting,
    refresh,
  };
}
