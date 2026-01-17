interface WelcomeProps {
  onNext: () => void;
}

export function Welcome({ onNext }: WelcomeProps) {
  return (
    <div className="onboarding-screen welcome-screen">
      <div className="onboarding-content">
        <h1>Welcome to Valet</h1>
        <p className="subtitle">Your AI-powered Mac maintenance assistant</p>

        <div className="feature-list">
          <div className="feature-item">
            <div className="feature-icon">🎤</div>
            <div className="feature-text">
              <h3>Voice-First Interface</h3>
              <p>Just speak naturally - "Clean my Mac" or "Why is it slow?"</p>
            </div>
          </div>

          <div className="feature-item">
            <div className="feature-icon">🧹</div>
            <div className="feature-text">
              <h3>Smart Cleaning</h3>
              <p>Safely remove caches, logs, and unnecessary files</p>
            </div>
          </div>

          <div className="feature-item">
            <div className="feature-icon">📊</div>
            <div className="feature-text">
              <h3>Real-Time Monitoring</h3>
              <p>Keep track of CPU, memory, disk space, and network activity</p>
            </div>
          </div>

          <div className="feature-item">
            <div className="feature-icon">🔒</div>
            <div className="feature-text">
              <h3>Safe & Secure</h3>
              <p>All operations are previewed before execution</p>
            </div>
          </div>
        </div>

        <div className="onboarding-actions">
          <button className="btn-primary" onClick={onNext}>
            Get Started
          </button>
        </div>
      </div>
    </div>
  );
}
