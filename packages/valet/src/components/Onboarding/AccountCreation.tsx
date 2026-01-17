import { useState } from 'react';
import { signUp, getCurrentUserId } from '../../lib/auth';
import { convexClient, isConvexConfigured } from '../../lib/convex';
import { api } from '../../../convex/_generated/api';
import { storeLlmProxyKeyAfterAuth } from '../../lib/keys';

interface AccountCreationProps {
  onNext: () => void;
  onBack: () => void;
}

type FormStatus = 'idle' | 'submitting' | 'error';

export function AccountCreation({ onNext, onBack }: AccountCreationProps) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [status, setStatus] = useState<FormStatus>('idle');
  const [errorMessage, setErrorMessage] = useState('');

  const validateForm = (): string | null => {
    if (!email.trim()) {
      return 'Email is required';
    }
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      return 'Please enter a valid email address';
    }
    if (!password) {
      return 'Password is required';
    }
    if (password.length < 8) {
      return 'Password must be at least 8 characters';
    }
    if (password !== confirmPassword) {
      return 'Passwords do not match';
    }
    return null;
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    const validationError = validateForm();
    if (validationError) {
      setErrorMessage(validationError);
      setStatus('error');
      return;
    }

    try {
      setStatus('submitting');
      setErrorMessage('');

      // Fallback to localStorage if Convex is not configured
      if (!isConvexConfigured()) {
        console.warn('Convex not configured, using localStorage fallback');

        // Store email in localStorage for later use
        localStorage.setItem('valet_user_email', email);

        // Persist trial start timestamp (only if not already set)
        const existingTrialStart = localStorage.getItem('valet_trial_start');
        if (!existingTrialStart) {
          localStorage.setItem('valet_trial_start', Date.now().toString());
        }

        onNext();
        return;
      }

      // 1. Sign up with Better-Auth
      const authResult = await signUp(email, password);

      if (!authResult.user?.id) {
        throw new Error('Sign up succeeded but user ID is missing');
      }

      // 2. Initialize trial and provision API key via Convex
      const trialResult = await convexClient.mutation(api.auth.signUp, {
        userId: authResult.user.id as any, // Convex ID type
        email: authResult.user.email,
      });

      // 3. Store the per-user llm-proxy key in Keychain
      if (trialResult.apiKey) {
        await storeLlmProxyKeyAfterAuth(trialResult.apiKey);

        // Emit event to notify App.tsx to refresh API keys
        window.dispatchEvent(new Event('auth-updated'));
      }

      // 4. Store trial start timestamp locally for quick access
      if (trialResult.trialEndsAt) {
        const trialStartTime = trialResult.trialEndsAt - (7 * 24 * 60 * 60 * 1000);
        localStorage.setItem('valet_trial_start', trialStartTime.toString());
      }

      // 5. Store email for UI display
      localStorage.setItem('valet_user_email', email);

      onNext();
    } catch (error) {
      console.error('Account creation failed:', error);
      setStatus('error');
      setErrorMessage(
        error instanceof Error ? error.message : 'Failed to create account'
      );
    }
  };

  return (
    <div className="onboarding-screen account-creation-screen">
      <div className="onboarding-content">
        <h1>Create Your Account</h1>
        <p className="subtitle">Start your 7-day free trial</p>

        <form className="account-form" onSubmit={handleSubmit}>
          <div className="form-group">
            <label htmlFor="email">Email Address</label>
            <input
              id="email"
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="you@example.com"
              disabled={status === 'submitting'}
              autoFocus
            />
          </div>

          <div className="form-group">
            <label htmlFor="password">Password</label>
            <input
              id="password"
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="At least 8 characters"
              disabled={status === 'submitting'}
            />
          </div>

          <div className="form-group">
            <label htmlFor="confirm-password">Confirm Password</label>
            <input
              id="confirm-password"
              type="password"
              value={confirmPassword}
              onChange={(e) => setConfirmPassword(e.target.value)}
              placeholder="Re-enter your password"
              disabled={status === 'submitting'}
            />
          </div>

          {status === 'error' && errorMessage && (
            <div className="error-message">{errorMessage}</div>
          )}

          <div className="trial-info">
            <p>
              ✓ 7-day free trial • No credit card required
              <br />
              ✓ Then $29/year to continue
            </p>
          </div>

          <div className="onboarding-actions">
            <button
              type="button"
              className="btn-secondary"
              onClick={onBack}
              disabled={status === 'submitting'}
            >
              Back
            </button>
            <button
              type="submit"
              className="btn-primary"
              disabled={status === 'submitting'}
            >
              {status === 'submitting' ? 'Creating Account...' : 'Continue'}
            </button>
          </div>
        </form>

        <div className="legal-links">
          <a href="#" onClick={(e) => e.preventDefault()}>Terms of Service</a>
          {' • '}
          <a href="#" onClick={(e) => e.preventDefault()}>Privacy Policy</a>
        </div>
      </div>
    </div>
  );
}
