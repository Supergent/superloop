import { formatBytes } from '../../lib/formatters';
import type { MoleStatusMetrics, MoleAnalyzeResult } from '../../lib/moleTypes';

interface TrialResultsProps {
  onNext: () => void;
  onBack: () => void;
  metrics?: MoleStatusMetrics | null;
  diskAnalysis?: MoleAnalyzeResult | null;
}

export function TrialResults({ onNext, onBack, metrics, diskAnalysis }: TrialResultsProps) {
  // Calculate trial end date from stored trial start timestamp
  const trialStartStr = localStorage.getItem('valet_trial_start');
  const parsedTime = trialStartStr ? parseInt(trialStartStr, 10) : NaN;
  const trialStartTime = !isNaN(parsedTime) ? parsedTime : Date.now();
  const trialEndDate = new Date(trialStartTime);
  trialEndDate.setDate(trialEndDate.getDate() + 7);
  const formattedEndDate = trialEndDate.toLocaleDateString('en-US', {
    month: 'long',
    day: 'numeric',
    year: 'numeric'
  });

  // Calculate potential space savings from top directories
  const potentialSavings = diskAnalysis?.directories
    ?.slice(0, 3)
    .reduce((total, dir) => total + dir.size, 0) || 0;

  return (
    <div className="onboarding-screen trial-results-screen">
      <div className="onboarding-content">
        <h1>You're All Set! 🎉</h1>
        <p className="subtitle">Your 7-day free trial has started</p>

        <div className="trial-info-card">
          <div className="trial-header">
            <div className="trial-icon">✓</div>
            <div className="trial-details">
              <h3>Free Trial Active</h3>
              <p>Ends on {formattedEndDate}</p>
            </div>
          </div>

          <div className="trial-features">
            <div className="feature-check">✓ Full access to all features</div>
            <div className="feature-check">✓ Voice-powered maintenance</div>
            <div className="feature-check">✓ Real-time system monitoring</div>
            <div className="feature-check">✓ Smart cleaning & optimization</div>
          </div>

          <div className="pricing-info">
            <div className="price-label">After trial:</div>
            <div className="price-amount">$29/year</div>
            <div className="price-note">Cancel anytime during trial</div>
          </div>
        </div>

        {metrics && (
          <div className="insights-card">
            <h3>Your Mac at a Glance</h3>
            <div className="insight-grid">
              <div className="insight-item">
                <div className="insight-label">Available Space</div>
                <div className="insight-value">{formatBytes(metrics.disk.available)}</div>
              </div>
              <div className="insight-item">
                <div className="insight-label">Memory Usage</div>
                <div className="insight-value">{metrics.memory.percentage.toFixed(0)}%</div>
              </div>
              {potentialSavings > 0 && (
                <div className="insight-item highlight">
                  <div className="insight-label">Potential Savings</div>
                  <div className="insight-value">{formatBytes(potentialSavings)}</div>
                </div>
              )}
            </div>
          </div>
        )}

        <div className="next-steps">
          <h3>What's Next?</h3>
          <div className="step-list">
            <div className="step-item">
              <div className="step-number">1</div>
              <div className="step-text">
                <strong>Try Voice Commands</strong>
                <br />
                Press Cmd+Shift+Space and say "How's my Mac?"
              </div>
            </div>
            <div className="step-item">
              <div className="step-number">2</div>
              <div className="step-text">
                <strong>Keep Your Mac Healthy</strong>
                <br />
                Monitor your system from the menubar
              </div>
            </div>
            <div className="step-item">
              <div className="step-number">3</div>
              <div className="step-text">
                <strong>Clean When Needed</strong>
                <br />
                Ask Valet to "Clean my Mac" anytime
              </div>
            </div>
          </div>
        </div>

        <div className="onboarding-actions">
          <button
            className="btn-secondary"
            onClick={onBack}
          >
            Back
          </button>
          <button
            className="btn-primary"
            onClick={onNext}
          >
            Start Using Valet
          </button>
        </div>
      </div>
    </div>
  );
}
