import React from 'react';
import { MoleStatusMetrics } from '../lib/moleTypes';
import { formatBytes, formatPercentage } from '../lib/formatters';

interface MetricsDisplayProps {
  metrics: MoleStatusMetrics;
}

export function MetricsDisplay({ metrics }: MetricsDisplayProps) {
  return (
    <div className="metrics-display">
      {/* CPU Metric */}
      <div className="metric-card">
        <div className="metric-icon">💻</div>
        <div className="metric-content">
          <div className="metric-label">CPU</div>
          <div className="metric-value">{formatPercentage(metrics.cpu.usage)}</div>
          <div className="metric-detail">{metrics.cpu.cores} cores</div>
        </div>
        <div className="metric-bar">
          <div
            className="metric-bar-fill"
            style={{
              width: `${metrics.cpu.usage}%`,
              backgroundColor: metrics.cpu.usage > 80 ? '#ef4444' : metrics.cpu.usage > 60 ? '#f59e0b' : '#10b981',
            }}
          />
        </div>
      </div>

      {/* Memory Metric */}
      <div className="metric-card">
        <div className="metric-icon">🧠</div>
        <div className="metric-content">
          <div className="metric-label">Memory</div>
          <div className="metric-value">{formatPercentage(metrics.memory.percentage)}</div>
          <div className="metric-detail">
            {formatBytes(metrics.memory.used)} / {formatBytes(metrics.memory.total)}
          </div>
        </div>
        <div className="metric-bar">
          <div
            className="metric-bar-fill"
            style={{
              width: `${metrics.memory.percentage}%`,
              backgroundColor: metrics.memory.percentage > 80 ? '#ef4444' : metrics.memory.percentage > 60 ? '#f59e0b' : '#10b981',
            }}
          />
        </div>
      </div>

      {/* Disk Metric */}
      <div className="metric-card">
        <div className="metric-icon">💾</div>
        <div className="metric-content">
          <div className="metric-label">Disk</div>
          <div className="metric-value">{formatPercentage(metrics.disk.percentage)}</div>
          <div className="metric-detail">
            {formatBytes(metrics.disk.available)} available
          </div>
        </div>
        <div className="metric-bar">
          <div
            className="metric-bar-fill"
            style={{
              width: `${metrics.disk.percentage}%`,
              backgroundColor: metrics.disk.percentage > 90 ? '#ef4444' : metrics.disk.percentage > 80 ? '#f59e0b' : '#10b981',
            }}
          />
        </div>
      </div>

      {/* Network Metric */}
      <div className="metric-card">
        <div className="metric-icon">🌐</div>
        <div className="metric-content">
          <div className="metric-label">Network</div>
          <div className="metric-value">
            <span className="network-direction">↓</span> {formatBytes(metrics.network.bytesReceived)}
          </div>
          <div className="metric-detail">
            <span className="network-direction">↑</span> {formatBytes(metrics.network.bytesSent)}
          </div>
        </div>
      </div>
    </div>
  );
}
