import { useState, useEffect } from 'react';
import { getSystemStatus, analyzeDiskUsage } from '../../lib/mole';
import { formatBytes } from '../../lib/formatters';
import type { MoleStatusMetrics, MoleAnalyzeResult } from '../../lib/moleTypes';

interface FirstScanProps {
  onNext: () => void;
  onBack: () => void;
}

type ScanStatus = 'idle' | 'scanning-status' | 'scanning-disk' | 'complete' | 'error';

export function FirstScan({ onNext, onBack }: FirstScanProps) {
  const [status, setStatus] = useState<ScanStatus>('idle');
  const [metrics, setMetrics] = useState<MoleStatusMetrics | null>(null);
  const [diskAnalysis, setDiskAnalysis] = useState<MoleAnalyzeResult | null>(null);
  const [errorMessage, setErrorMessage] = useState<string>('');

  useEffect(() => {
    // Auto-start scan on mount
    startScan();
  }, []);

  const startScan = async () => {
    try {
      setStatus('scanning-status');
      setErrorMessage('');

      // Step 1: Get system status
      const statusMetrics = await getSystemStatus();
      setMetrics(statusMetrics);

      // Step 2: Analyze disk usage
      setStatus('scanning-disk');
      const analysis = await analyzeDiskUsage();
      setDiskAnalysis(analysis);

      setStatus('complete');
    } catch (error) {
      console.error('First scan failed:', error);
      setStatus('error');
      setErrorMessage(error instanceof Error ? error.message : 'Unknown error');
    }
  };

  const handleRetry = () => {
    startScan();
  };

  const handleFinish = () => {
    onNext();
  };

  return (
    <div className="onboarding-screen first-scan-screen">
      <div className="onboarding-content">
        <h1>Initial System Scan</h1>
        <p className="subtitle">Let's analyze your Mac's current state</p>

        <div className="scan-container">
          {status === 'scanning-status' && (
            <div className="scan-item">
              <div className="spinner"></div>
              <p>Checking system metrics...</p>
            </div>
          )}

          {status === 'scanning-disk' && (
            <div className="scan-item">
              <div className="spinner"></div>
              <p>Analyzing disk usage...</p>
            </div>
          )}

          {status === 'error' && (
            <div className="scan-item error">
              <div className="status-icon">✗</div>
              <p>Scan failed</p>
              {errorMessage && <p className="error-message">{errorMessage}</p>}
              <button className="btn-secondary" onClick={handleRetry}>
                Retry
              </button>
            </div>
          )}

          {status === 'complete' && metrics && diskAnalysis && (
            <div className="scan-results">
              <div className="result-header">
                <div className="status-icon success">✓</div>
                <h2>Scan Complete!</h2>
              </div>

              <div className="metrics-summary">
                <div className="metric-card">
                  <div className="metric-label">CPU Usage</div>
                  <div className="metric-value">{metrics.cpu.usage.toFixed(1)}%</div>
                </div>

                <div className="metric-card">
                  <div className="metric-label">Memory Used</div>
                  <div className="metric-value">{metrics.memory.percentage.toFixed(1)}%</div>
                </div>

                <div className="metric-card">
                  <div className="metric-label">Disk Used</div>
                  <div className="metric-value">{metrics.disk.percentage.toFixed(1)}%</div>
                </div>

                <div className="metric-card">
                  <div className="metric-label">Available Space</div>
                  <div className="metric-value">{formatBytes(metrics.disk.available)}</div>
                </div>
              </div>

              <div className="disk-analysis">
                <h3>Top Space Consumers</h3>
                <div className="directory-list">
                  {diskAnalysis.directories.slice(0, 5).map((dir, idx) => (
                    <div key={idx} className="directory-item">
                      <div className="directory-name">{dir.path}</div>
                      <div className="directory-size">{formatBytes(dir.size)}</div>
                    </div>
                  ))}
                </div>
              </div>

              <div className="scan-summary">
                <p>
                  Your Mac has been scanned successfully. You can now start using Valet
                  to maintain and optimize your system!
                </p>
              </div>
            </div>
          )}
        </div>

        <div className="onboarding-actions">
          <button
            className="btn-secondary"
            onClick={onBack}
            disabled={status === 'scanning-status' || status === 'scanning-disk'}
          >
            Back
          </button>
          <button
            className="btn-primary"
            onClick={handleFinish}
            disabled={status !== 'complete'}
          >
            Get Started
          </button>
        </div>
      </div>
    </div>
  );
}
