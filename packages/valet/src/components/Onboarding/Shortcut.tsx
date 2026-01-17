import { useState } from 'react';

interface ShortcutProps {
  onNext: () => void;
  onBack: () => void;
}

export function Shortcut({ onNext, onBack }: ShortcutProps) {
  const [tested, setTested] = useState(false);

  const handleTest = () => {
    setTested(true);
    // In a real implementation, this would trigger the actual shortcut test
    setTimeout(() => {
      alert('Shortcut test: Press Cmd+Shift+Space to activate voice input!');
    }, 100);
  };

  return (
    <div className="onboarding-screen shortcut-screen">
      <div className="onboarding-content">
        <h1>Voice Activation Shortcut</h1>
        <p className="subtitle">Use a keyboard shortcut to quickly activate Valet</p>

        <div className="shortcut-display">
          <div className="shortcut-keys">
            <kbd>⌘</kbd>
            <span className="plus">+</span>
            <kbd>⇧</kbd>
            <span className="plus">+</span>
            <kbd>Space</kbd>
          </div>
          <p className="shortcut-description">Press this combination to start voice input</p>
        </div>

        <div className="shortcut-info">
          <h3>How it works:</h3>
          <ol>
            <li>Press <strong>Cmd+Shift+Space</strong> from anywhere on your Mac</li>
            <li>Speak your request (e.g., "How's my Mac?" or "Clean my caches")</li>
            <li>Valet will process your request and speak the response</li>
          </ol>

          <div className="tip-box">
            <p>
              <strong>Tip:</strong> You can also click the microphone icon in the menubar
              dropdown to activate voice input.
            </p>
          </div>
        </div>

        <div className="test-section">
          <button className="btn-secondary" onClick={handleTest}>
            Test Shortcut
          </button>
          {tested && (
            <p className="test-result">✓ Ready to use!</p>
          )}
        </div>

        <div className="onboarding-actions">
          <button className="btn-secondary" onClick={onBack}>
            Back
          </button>
          <button className="btn-primary" onClick={onNext}>
            Continue
          </button>
        </div>
      </div>
    </div>
  );
}
