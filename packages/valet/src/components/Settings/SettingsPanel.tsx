import React, { useState, useEffect } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { useSettings } from '../../lib/settings';
import { setAutostart } from '../../lib/autostart';
import { ApiKeysModal } from './ApiKeysModal';
import { getCurrentUserId } from '../../lib/auth';
import { convexClient, isConvexConfigured } from '../../lib/convex';
import { api } from '../../../convex/_generated/api';

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

  // Alert thresholds (in GB)
  const [diskWarningThreshold, setDiskWarningThreshold] = useState(
    parseInt(settings.diskWarningThreshold || '20', 10)
  );
  const [diskCriticalThreshold, setDiskCriticalThreshold] = useState(
    parseInt(settings.diskCriticalThreshold || '10', 10)
  );

  // Local input state for thresholds (allows multi-digit typing)
  const [diskWarningInput, setDiskWarningInput] = useState(
    settings.diskWarningThreshold || '20'
  );
  const [diskCriticalInput, setDiskCriticalInput] = useState(
    settings.diskCriticalThreshold || '10'
  );

  // API keys modal state
  const [showApiKeysModal, setShowApiKeysModal] = useState(false);

  // Subscription status from backend
  const [subscriptionStatus, setSubscriptionStatus] = useState<{
    status: string;
    trialStartedAt?: number;
    trialEndsAt?: number;
    subscriptionEndsAt?: number;
  } | null>(null);
  const [subscriptionLoading, setSubscriptionLoading] = useState(false);

  // Fetch subscription status from backend
  useEffect(() => {
    const fetchSubscriptionStatus = async () => {
      if (!isConvexConfigured()) {
        return; // Fall back to localStorage
      }

      try {
        setSubscriptionLoading(true);
        const userId = await getCurrentUserId();

        if (!userId) {
          return; // Not authenticated, use localStorage
        }

        const status = await convexClient.query(api.auth.getSubscriptionStatus, {
          userId: userId as any, // Convex ID type
        });

        if (status) {
          setSubscriptionStatus(status as any);
        }
      } catch (error) {
        console.error('Failed to fetch subscription status:', error);
      } finally {
        setSubscriptionLoading(false);
      }
    };

    fetchSubscriptionStatus();
  }, []);

  // Update local state when settings change
  useEffect(() => {
    setVoiceEnabled(settings.voiceEnabled === 'true');
    setMonitoringFrequency(parseInt(settings.monitoringFrequency || '30', 10));
    setNotificationMode(settings.notificationMode || 'critical');
    setAutoStart(settings.autoStart === 'true');
    setDiskWarningThreshold(parseInt(settings.diskWarningThreshold || '20', 10));
    setDiskCriticalThreshold(parseInt(settings.diskCriticalThreshold || '10', 10));
    setDiskWarningInput(settings.diskWarningThreshold || '20');
    setDiskCriticalInput(settings.diskCriticalThreshold || '10');
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

  const handleDiskWarningThresholdBlur = async () => {
    const value = parseInt(diskWarningInput, 10);
    // Prevent NaN/empty values from being persisted - revert to previous valid value
    if (isNaN(value) || value <= 0) {
      console.warn('Warning threshold must be a valid positive number');
      setDiskWarningInput(diskWarningThreshold.toString());
      return;
    }
    // Ensure warning threshold is greater than critical threshold
    if (value <= diskCriticalThreshold) {
      console.warn('Warning threshold must be greater than critical threshold');
      setDiskWarningInput(diskWarningThreshold.toString());
      return;
    }
    setDiskWarningThreshold(value);
    await updateSetting('diskWarningThreshold', value.toString());
  };

  const handleDiskCriticalThresholdBlur = async () => {
    const value = parseInt(diskCriticalInput, 10);
    // Prevent NaN/empty values from being persisted - revert to previous valid value
    if (isNaN(value) || value <= 0) {
      console.warn('Critical threshold must be a valid positive number');
      setDiskCriticalInput(diskCriticalThreshold.toString());
      return;
    }
    // Ensure critical threshold is less than warning threshold
    if (value >= diskWarningThreshold) {
      console.warn('Critical threshold must be less than warning threshold');
      setDiskCriticalInput(diskCriticalThreshold.toString());
      return;
    }
    setDiskCriticalThreshold(value);
    await updateSetting('diskCriticalThreshold', value.toString());
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

        {/* Alert Thresholds Settings */}
        <section className="settings-section">
          <h3 className="section-title">Alert Thresholds</h3>
          <div className="setting-item">
            <div className="setting-info">
              <label htmlFor="disk-warning-threshold">Disk Warning (GB)</label>
              <span className="setting-description">
                Show warning when free disk space falls below this amount
              </span>
            </div>
            <input
              id="disk-warning-threshold"
              type="number"
              min="1"
              max="1000"
              value={diskWarningInput}
              onChange={(e) => setDiskWarningInput(e.target.value)}
              onBlur={handleDiskWarningThresholdBlur}
            />
          </div>
          <div className="setting-item">
            <div className="setting-info">
              <label htmlFor="disk-critical-threshold">Disk Critical (GB)</label>
              <span className="setting-description">
                Show critical alert when free disk space falls below this amount
              </span>
            </div>
            <input
              id="disk-critical-threshold"
              type="number"
              min="1"
              max="1000"
              value={diskCriticalInput}
              onChange={(e) => setDiskCriticalInput(e.target.value)}
              onBlur={handleDiskCriticalThresholdBlur}
            />
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

        {/* Account & Subscription Section */}
        <section className="settings-section">
          <h3 className="section-title">Account & Subscription</h3>
          <div className="account-info">
            <div className="account-row">
              <span className="account-label">Email:</span>
              <span className="account-value">
                {localStorage.getItem('valet_user_email') || 'Not signed in'}
              </span>
            </div>
            <div className="account-row">
              <span className="account-label">Status:</span>
              <span className="account-value trial-badge">
                {(() => {
                  if (subscriptionLoading) {
                    return 'Loading...';
                  }

                  // Use backend status if available
                  if (subscriptionStatus) {
                    if (subscriptionStatus.status === 'active') {
                      return '✓ Subscribed';
                    }
                    if (subscriptionStatus.status === 'trial' && subscriptionStatus.trialEndsAt) {
                      const isExpired = Date.now() > subscriptionStatus.trialEndsAt;
                      return isExpired ? '⚠️ Trial Expired' : '✓ Free Trial Active';
                    }
                    if (subscriptionStatus.status === 'expired') {
                      return '⚠️ Trial Expired';
                    }
                    return '⚠️ No Active Subscription';
                  }

                  // Fall back to localStorage
                  const trialStartStr = localStorage.getItem('valet_trial_start');
                  const parsedTime = trialStartStr ? parseInt(trialStartStr, 10) : NaN;
                  const trialStartTime = !isNaN(parsedTime) ? parsedTime : Date.now();
                  const endDate = new Date(trialStartTime);
                  endDate.setDate(endDate.getDate() + 7);
                  const isExpired = endDate.getTime() < Date.now();
                  return isExpired ? '⚠️ Trial Expired' : '✓ Free Trial Active';
                })()}
              </span>
            </div>
            <div className="account-row">
              <span className="account-label">
                {subscriptionStatus?.status === 'active' ? 'Subscription Ends:' : 'Trial Ends:'}
              </span>
              <span className="account-value">
                {(() => {
                  // Use backend status if available
                  if (subscriptionStatus) {
                    const endTime = subscriptionStatus.status === 'active'
                      ? subscriptionStatus.subscriptionEndsAt
                      : subscriptionStatus.trialEndsAt;

                    if (!endTime) return 'N/A';

                    const endDate = new Date(endTime);
                    return endDate.toLocaleDateString('en-US', {
                      month: 'short',
                      day: 'numeric',
                      year: 'numeric'
                    });
                  }

                  // Fall back to localStorage
                  const trialStartStr = localStorage.getItem('valet_trial_start');
                  const parsedTime = trialStartStr ? parseInt(trialStartStr, 10) : NaN;
                  const trialStartTime = !isNaN(parsedTime) ? parsedTime : Date.now();
                  const endDate = new Date(trialStartTime);
                  endDate.setDate(endDate.getDate() + 7);
                  return endDate.toLocaleDateString('en-US', {
                    month: 'short',
                    day: 'numeric',
                    year: 'numeric'
                  });
                })()}
              </span>
            </div>
            <div className="account-row">
              <span className="account-label">Price:</span>
              <span className="account-value">
                {subscriptionStatus?.status === 'active' ? '$29/year' : '$29/year after trial'}
              </span>
            </div>
          </div>
          <div className="account-actions">
            {(() => {
              // Determine if subscription is expired
              let isExpired = false;

              if (subscriptionStatus) {
                if (subscriptionStatus.status === 'trial' && subscriptionStatus.trialEndsAt) {
                  isExpired = Date.now() > subscriptionStatus.trialEndsAt;
                } else if (subscriptionStatus.status === 'expired') {
                  isExpired = true;
                } else if (subscriptionStatus.status === 'active' && subscriptionStatus.subscriptionEndsAt) {
                  isExpired = Date.now() > subscriptionStatus.subscriptionEndsAt;
                }
              } else {
                // Fall back to localStorage
                const trialStartStr = localStorage.getItem('valet_trial_start');
                const parsedTime = trialStartStr ? parseInt(trialStartStr, 10) : NaN;
                const trialStartTime = !isNaN(parsedTime) ? parsedTime : Date.now();
                const endDate = new Date(trialStartTime);
                endDate.setDate(endDate.getDate() + 7);
                isExpired = endDate.getTime() < Date.now();
              }

              if (isExpired) {
                return (
                  <>
                    <div className="expired-trial-message">
                      Your trial has expired. Subscribe to continue using Valet's voice assistant features.
                    </div>
                    <button
                      className="settings-button primary"
                      onClick={async () => {
                        // TODO: Integrate with Stripe payment flow
                        // For now, open Stripe Checkout or billing portal
                        console.log('Subscribe clicked');
                        alert('Subscription flow coming soon!');
                      }}
                    >
                      Subscribe Now ($29/year)
                    </button>
                  </>
                );
              }

              return (
                <button
                  className="settings-button secondary"
                  onClick={async () => {
                    // TODO: Open Stripe billing portal when available
                    console.log('Manage account clicked');
                    alert('Account management coming soon!');
                  }}
                >
                  Manage Account
                </button>
              );
            })()}
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
