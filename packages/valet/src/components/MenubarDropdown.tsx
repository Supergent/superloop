import React from 'react';
import { HealthStatus, MoleStatusMetrics } from '../lib/moleTypes';

interface MenubarDropdownProps {
  health: HealthStatus;
  metrics: MoleStatusMetrics | null;
  loading: boolean;
  error: string | null;
  aiWorking?: boolean;
  aiResponse?: string;
  metricsSlot?: React.ReactNode;
  actionsSlot?: React.ReactNode;
  voiceSlot?: React.ReactNode;
  activitySlot?: React.ReactNode;
}

export function MenubarDropdown({
  health,
  metrics,
  loading,
  error,
  aiWorking = false,
  aiResponse,
  metricsSlot,
  actionsSlot,
  voiceSlot,
  activitySlot,
}: MenubarDropdownProps) {
  const getHealthLabel = (status: HealthStatus): string => {
    switch (status) {
      case 'good':
        return 'Healthy';
      case 'warning':
        return 'Warning';
      case 'critical':
        return 'Critical';
    }
  };

  const getHealthColor = (status: HealthStatus): string => {
    switch (status) {
      case 'good':
        return '#10b981'; // green
      case 'warning':
        return '#f59e0b'; // yellow
      case 'critical':
        return '#ef4444'; // red
    }
  };

  return (
    <div className="menubar-dropdown">
      {/* Header Section */}
      <div className="dropdown-header">
        <div className="header-title">
          <h2>Valet</h2>
          <span className="header-subtitle">Mac Maintenance Assistant</span>
        </div>
        <div className="header-status">
          <div
            className="status-indicator"
            style={{ backgroundColor: getHealthColor(health) }}
          />
          <span className="status-label">{getHealthLabel(health)}</span>
        </div>
      </div>

      {/* Status Section */}
      {loading && (
        <div className="dropdown-loading">
          <div className="loading-spinner" />
          <span>Loading system metrics...</span>
        </div>
      )}

      {error && (
        <div className="dropdown-error">
          <span className="error-icon">⚠️</span>
          <span>{error}</span>
        </div>
      )}

      {/* AI Working Indicator */}
      {aiWorking && (
        <div className="dropdown-ai-working">
          <div className="loading-spinner" />
          <span>AI is thinking...</span>
        </div>
      )}

      {/* AI Response Display */}
      {aiResponse && aiResponse.trim() && (
        <div className="dropdown-section ai-response-section">
          <h3 className="section-title">AI Response</h3>
          <div className="ai-response-text">{aiResponse}</div>
        </div>
      )}

      {/* Metrics Section */}
      {metrics && metricsSlot && (
        <div className="dropdown-section metrics-section">
          {metricsSlot}
        </div>
      )}

      {/* Quick Actions Section */}
      {actionsSlot && (
        <div className="dropdown-section actions-section">
          <h3 className="section-title">Quick Actions</h3>
          {actionsSlot}
        </div>
      )}

      {/* Voice Input Section */}
      {voiceSlot && (
        <div className="dropdown-section voice-section">
          {voiceSlot}
        </div>
      )}

      {/* Activity Log Section */}
      {activitySlot && (
        <div className="dropdown-section activity-section">
          <h3 className="section-title">Recent Activity</h3>
          {activitySlot}
        </div>
      )}
    </div>
  );
}
