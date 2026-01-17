import { useState, useEffect } from 'react';
import { ensureMoleInstalled } from '../../lib/mole';

interface MoleCheckProps {
  onNext: () => void;
  onBack: () => void;
}

type CheckStatus = 'checking' | 'installing' | 'success' | 'error';

export function MoleCheck({ onNext, onBack }: MoleCheckProps) {
  const [status, setStatus] = useState<CheckStatus>('checking');
  const [errorMessage, setErrorMessage] = useState<string>('');
  const [molePath, setMolePath] = useState<string>('');

  useEffect(() => {
    checkMole();
  }, []);

  const checkMole = async () => {
    try {
      setStatus('checking');
      setErrorMessage('');

      // This will check if Mole is already installed, or install it from resources
      const path = await ensureMoleInstalled();
      setMolePath(path);
      setStatus('success');
    } catch (error) {
      console.error('Mole check failed:', error);
      setStatus('error');
      setErrorMessage(error instanceof Error ? error.message : 'Unknown error');
    }
  };

  const handleRetry = () => {
    checkMole();
  };

  return (
    <div className="onboarding-screen mole-check-screen">
      <div className="onboarding-content">
        <h1>Setting Up Mole</h1>
        <p className="subtitle">Valet uses the Mole CLI to perform Mac maintenance tasks</p>

        <div className="status-container">
          {status === 'checking' && (
            <div className="status-item">
              <div className="spinner"></div>
              <p>Checking for Mole installation...</p>
            </div>
          )}

          {status === 'installing' && (
            <div className="status-item">
              <div className="spinner"></div>
              <p>Installing Mole from app resources...</p>
            </div>
          )}

          {status === 'success' && (
            <div className="status-item success">
              <div className="status-icon">✓</div>
              <p>Mole is ready!</p>
              {molePath && <p className="detail">Installed at: {molePath}</p>}
            </div>
          )}

          {status === 'error' && (
            <div className="status-item error">
              <div className="status-icon">✗</div>
              <p>Failed to install Mole</p>
              {errorMessage && <p className="error-message">{errorMessage}</p>}
              <button className="btn-secondary" onClick={handleRetry}>
                Retry
              </button>
            </div>
          )}
        </div>

        <div className="onboarding-actions">
          <button className="btn-secondary" onClick={onBack}>
            Back
          </button>
          <button
            className="btn-primary"
            onClick={onNext}
            disabled={status !== 'success'}
          >
            Continue
          </button>
        </div>
      </div>
    </div>
  );
}
