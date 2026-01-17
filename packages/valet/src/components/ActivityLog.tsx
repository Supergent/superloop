import React from 'react';

export interface ActivityLogEntry {
  id: string;
  timestamp: number;
  type: 'clean' | 'optimize' | 'scan' | 'uninstall' | 'other';
  description: string;
  details?: string;
}

export interface ActivityLogProps {
  entries: ActivityLogEntry[];
  maxEntries?: number;
}

export function ActivityLog({ entries, maxEntries = 5 }: ActivityLogProps) {
  const displayEntries = entries.slice(0, maxEntries);

  if (displayEntries.length === 0) {
    return (
      <div className="activity-log empty">
        <p className="empty-message">No recent activity</p>
      </div>
    );
  }

  const formatTimestamp = (timestamp: number): string => {
    const now = Date.now();
    const diff = now - timestamp;
    const minutes = Math.floor(diff / 60000);
    const hours = Math.floor(diff / 3600000);
    const days = Math.floor(diff / 86400000);

    if (minutes < 1) return 'Just now';
    if (minutes < 60) return `${minutes}m ago`;
    if (hours < 24) return `${hours}h ago`;
    return `${days}d ago`;
  };

  const getActivityIcon = (type: ActivityLogEntry['type']): string => {
    switch (type) {
      case 'clean':
        return '🧹';
      case 'optimize':
        return '⚡';
      case 'scan':
        return '🔍';
      case 'uninstall':
        return '🗑️';
      default:
        return '📋';
    }
  };

  return (
    <div className="activity-log">
      {displayEntries.map((entry) => (
        <div key={entry.id} className="activity-entry">
          <span className="activity-icon">{getActivityIcon(entry.type)}</span>
          <div className="activity-content">
            <div className="activity-description">{entry.description}</div>
            {entry.details && <div className="activity-details">{entry.details}</div>}
          </div>
          <span className="activity-time">{formatTimestamp(entry.timestamp)}</span>
        </div>
      ))}
    </div>
  );
}
