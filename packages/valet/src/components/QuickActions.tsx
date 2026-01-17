import React from 'react';

export interface QuickActionsProps {
  onClean: () => void;
  onOptimize: () => void;
  onDeepScan: () => void;
  disabled?: boolean;
}

export function QuickActions({
  onClean,
  onOptimize,
  onDeepScan,
  disabled = false,
}: QuickActionsProps) {
  return (
    <div className="quick-actions">
      <button
        className="action-button action-clean"
        onClick={onClean}
        disabled={disabled}
      >
        <span className="action-icon">🧹</span>
        <span className="action-label">Clean</span>
      </button>

      <button
        className="action-button action-optimize"
        onClick={onOptimize}
        disabled={disabled}
      >
        <span className="action-icon">⚡</span>
        <span className="action-label">Optimize</span>
      </button>

      <button
        className="action-button action-scan"
        onClick={onDeepScan}
        disabled={disabled}
      >
        <span className="action-icon">🔍</span>
        <span className="action-label">Deep Scan</span>
      </button>
    </div>
  );
}
