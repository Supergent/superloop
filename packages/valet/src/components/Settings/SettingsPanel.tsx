import React, { useState, useEffect } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { useSettings } from '../../lib/settings';
import { setAutostart } from '../../lib/autostart';
import { ApiKeysModal } from './ApiKeysModal';

interface SettingsPanelProps {
  onClose?: () => void;
  onKeysChanged?: () => void;
}

export function SettingsPanel({ onClose, onKeysChanged }: SettingsPanelProps) {
  const { settings, loading, updateSetting } = useSettings();

  // Voice activation toggle
  const [voiceEnabled, setVoiceEnabled] = useState(
    settings.voiceEnabled === 'true'
  );

  // Monitoring frequency (in minutes)
  const [monitoringFrequency, setMonitoringFrequency] = useState(
    parseInt(settings.monitoringFrequency || '30', 10)
  );

  // Notification preferences
  const [notificationMode, setNotificationMode] = useState(
    settings.notificationMode || 'critical'
  );

  // Auto-start preference
  const [autoStart, setAutoStart] = useState(
    settings.autoStart === 'true'
  );

  // API keys modal state
  const [showApiKeysModal, setShowApiKeysModal] = useState(false);

  // Update local state when settings change
  useEffect(() => {
    setVoiceEnabled(settings.voiceEnabled === 'true');
    setMonitoringFrequency(parseInt(settings.monitoringFrequency || '30', 10));
    setNotificationMode(settings.notificationMode || 'critical');
    setAutoStart(settings.autoStart === 'true');
  }, [settings]);

  const handleVoiceToggle = async (checked: boolean) => {
    setVoiceEnabled(checked);
    await updateSetting('voiceEnabled', checked.toString());

    // Emit custom event for any listeners (e.g., App.tsx)
    window.dispatchEvent(new CustomEvent('setting-changed', {
      detail: { key: 'voiceEnabled', value: checked.toString() }
    }));
  };

  const handleMonitoringFrequencyChange = async (value: number) => {
    setMonitoringFrequency(value);
    await updateSetting('monitoringFrequency', value.toString());

    // Update the backend monitoring configuration
    try {
      await invoke('update_monitoring_config', {
        enabled: value > 0, // Disable if manual only (0)
        interval_minutes: value > 0 ? value : 30, // Use 30 as default for manual
      });
    } catch (error) {
      console.error('Failed to update monitoring config:', error);
    }
  };

  const handleNotificationModeChange = async (value: string) => {
    setNotificationMode(value);
    await updateSetting('notificationMode', value);
  };

  const handleAutoStartToggle = async (checked: boolean) => {
    setAutoStart(checked);
    await updateSetting('autoStart', checked.toString());

    // Update the backend autostart configuration
    try {
      await setAutostart(checked);
    } catch (error) {
      console.error('Failed to update autostart:', error);
    }
  };

  if (loading) {
    return (
      <div className="settings-panel">
        <div className="settings-loading">
          <div className="loading-spinner" />
          <span>Loading settings...</span>
        </div>
      </div>
    );
  }

  return (
    <div className="settings-panel">
      {/* Header */}
      <div className="settings-header">
        <h2>Settings</h2>
        {onClose && (
          <button className="close-button" onClick={onClose}>
            ✕
          </button>
        )}
      </div>

      {/* Settings Sections */}
      <div className="settings-content">
        {/* Voice Settings */}
        <section className="settings-section">
          <h3 className="section-title">Voice Activation</h3>
          <div className="setting-item">
            <div className="setting-info">
              <label htmlFor="voice-enabled">Enable Voice Input</label>
              <span className="setting-description">
                Activate voice input with Cmd+Shift+Space
              </span>
            </div>
            <input
              id="voice-enabled"
              type="checkbox"
              checked={voiceEnabled}
              onChange={(e) => handleVoiceToggle(e.target.checked)}
            />
          </div>
        </section>

        {/* Monitoring Settings */}
        <section className="settings-section">
          <h3 className="section-title">Background Monitoring</h3>
          <div className="setting-item">
            <div className="setting-info">
              <label htmlFor="monitoring-frequency">Check Frequency</label>
              <span className="setting-description">
                How often to check system status
              </span>
            </div>
            <select
              id="monitoring-frequency"
              value={monitoringFrequency}
              onChange={(e) => handleMonitoringFrequencyChange(parseInt(e.target.value, 10))}
            >
              <option value="15">Every 15 minutes</option>
              <option value="30">Every 30 minutes</option>
              <option value="60">Every hour</option>
              <option value="0">Manual only</option>
            </select>
          </div>
        </section>

        {/* Notification Settings */}
        <section className="settings-section">
          <h3 className="section-title">Notifications</h3>
          <div className="setting-item">
            <div className="setting-info">
              <label htmlFor="notification-mode">Notification Mode</label>
              <span className="setting-description">
                When to show system notifications
              </span>
            </div>
            <select
              id="notification-mode"
              value={notificationMode}
              onChange={(e) => handleNotificationModeChange(e.target.value)}
            >
              <option value="critical">Critical issues only</option>
              <option value="suggestions">Suggestions and warnings</option>
              <option value="weekly">Weekly summary</option>
              <option value="none">None</option>
            </select>
          </div>
        </section>

        {/* General Settings */}
        <section className="settings-section">
          <h3 className="section-title">General</h3>
          <div className="setting-item">
            <div className="setting-info">
              <label htmlFor="auto-start">Launch at Login</label>
              <span className="setting-description">
                Start Valet automatically when you log in
              </span>
            </div>
            <input
              id="auto-start"
              type="checkbox"
              checked={autoStart}
              onChange={(e) => handleAutoStartToggle(e.target.checked)}
            />
          </div>
        </section>

        {/* API Keys Section */}
        <section className="settings-section">
          <h3 className="section-title">API Keys</h3>
          <div className="setting-info">
            <span className="setting-description">
              API keys are stored securely in macOS Keychain
            </span>
          </div>
          <button
            className="settings-button secondary"
            onClick={() => setShowApiKeysModal(true)}
          >
            Manage API Keys
          </button>
        </section>

        {/* About Section */}
        <section className="settings-section">
          <h3 className="section-title">About</h3>
          <div className="about-info">
            <div className="about-row">
              <span className="about-label">Version:</span>
              <span className="about-value">1.0.0</span>
            </div>
            <div className="about-row">
              <span className="about-label">Mole Version:</span>
              <span className="about-value">Latest</span>
            </div>
          </div>
          <div className="about-links">
            <a href="#" className="settings-link">Privacy Policy</a>
            <a href="#" className="settings-link">Terms of Service</a>
          </div>
        </section>
      </div>

      {/* API Keys Modal */}
      <ApiKeysModal
        isOpen={showApiKeysModal}
        onClose={() => setShowApiKeysModal(false)}
        onKeysChanged={onKeysChanged}
      />
    </div>
  );
}
