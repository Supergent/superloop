import { describe, it, expect, beforeEach, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { OnboardingFlow } from '../OnboardingFlow';

// Mock child components
vi.mock('../Welcome', () => ({
  Welcome: ({ onNext }: { onNext: () => void }) => (
    <div data-testid="welcome-screen">
      <button onClick={onNext}>Next from Welcome</button>
    </div>
  ),
}));

vi.mock('../AccountCreation', () => ({
  AccountCreation: ({ onNext, onBack }: { onNext: () => void; onBack: () => void }) => (
    <div data-testid="account-creation-screen">
      <button onClick={onBack}>Back</button>
      <button onClick={onNext}>Next from Account</button>
    </div>
  ),
}));

vi.mock('../MoleCheck', () => ({
  MoleCheck: ({ onNext, onBack }: { onNext: () => void; onBack: () => void }) => (
    <div data-testid="mole-check-screen">
      <button onClick={onBack}>Back</button>
      <button onClick={onNext}>Next from Mole</button>
    </div>
  ),
}));

vi.mock('../Permissions', () => ({
  Permissions: ({ onNext, onBack }: { onNext: () => void; onBack: () => void }) => (
    <div data-testid="permissions-screen">
      <button onClick={onBack}>Back</button>
      <button onClick={onNext}>Next from Permissions</button>
    </div>
  ),
}));

vi.mock('../Shortcut', () => ({
  Shortcut: ({ onNext, onBack }: { onNext: () => void; onBack: () => void }) => (
    <div data-testid="shortcut-screen">
      <button onClick={onBack}>Back</button>
      <button onClick={onNext}>Next from Shortcut</button>
    </div>
  ),
}));

vi.mock('../FirstScan', () => ({
  FirstScan: ({ onNext, onBack }: { onNext: () => void; onBack: () => void }) => (
    <div data-testid="first-scan-screen">
      <button onClick={onBack}>Back</button>
      <button
        onClick={() => {
          // Simulate passing scan data
          const mockData = {
            metrics: {
              disk: { available: 100000000000, total: 500000000000, percentage: 80 },
              memory: { used: 8000000000, total: 16000000000, percentage: 50 },
              cpu: { percentage: 25 },
            },
            diskAnalysis: {
              directories: [
                { path: '/path/to/large', size: 5000000000 },
                { path: '/path/to/medium', size: 3000000000 },
                { path: '/path/to/small', size: 1000000000 },
              ],
            },
          };
          onNext(mockData);
        }}
      >
        Next from FirstScan
      </button>
    </div>
  ),
}));

vi.mock('../TrialResults', () => ({
  TrialResults: ({
    onNext,
    onBack,
    metrics,
    diskAnalysis,
  }: {
    onNext: () => void;
    onBack: () => void;
    metrics?: any;
    diskAnalysis?: any;
  }) => (
    <div data-testid="trial-results-screen">
      <button onClick={onBack}>Back</button>
      <button onClick={onNext}>Next from Trial</button>
      {metrics && <div data-testid="trial-metrics">Metrics present</div>}
      {diskAnalysis && <div data-testid="trial-disk-analysis">Disk analysis present</div>}
    </div>
  ),
}));

describe('OnboardingFlow', () => {
  beforeEach(() => {
    localStorage.clear();
  });

  describe('Step Navigation', () => {
    it('should start at welcome screen', () => {
      render(<OnboardingFlow onComplete={vi.fn()} />);
      expect(screen.getByTestId('welcome-screen')).toBeInTheDocument();
    });

    it('should navigate from welcome to account-creation', async () => {
      const user = userEvent.setup();
      render(<OnboardingFlow onComplete={vi.fn()} />);

      await user.click(screen.getByText('Next from Welcome'));

      expect(screen.getByTestId('account-creation-screen')).toBeInTheDocument();
      expect(screen.queryByTestId('welcome-screen')).not.toBeInTheDocument();
    });

    it('should navigate from account-creation to mole-check', async () => {
      const user = userEvent.setup();
      render(<OnboardingFlow onComplete={vi.fn()} />);

      // Navigate to account-creation
      await user.click(screen.getByText('Next from Welcome'));

      // Navigate to mole-check
      await user.click(screen.getByText('Next from Account'));

      expect(screen.getByTestId('mole-check-screen')).toBeInTheDocument();
      expect(screen.queryByTestId('account-creation-screen')).not.toBeInTheDocument();
    });

    it('should complete full forward flow: welcome → account → mole → permissions → shortcut → scan → trial', async () => {
      const user = userEvent.setup();
      render(<OnboardingFlow onComplete={vi.fn()} />);

      // Welcome → Account Creation
      await user.click(screen.getByText('Next from Welcome'));
      expect(screen.getByTestId('account-creation-screen')).toBeInTheDocument();

      // Account Creation → Mole Check
      await user.click(screen.getByText('Next from Account'));
      expect(screen.getByTestId('mole-check-screen')).toBeInTheDocument();

      // Mole Check → Permissions
      await user.click(screen.getByText('Next from Mole'));
      expect(screen.getByTestId('permissions-screen')).toBeInTheDocument();

      // Permissions → Shortcut
      await user.click(screen.getByText('Next from Permissions'));
      expect(screen.getByTestId('shortcut-screen')).toBeInTheDocument();

      // Shortcut → First Scan
      await user.click(screen.getByText('Next from Shortcut'));
      expect(screen.getByTestId('first-scan-screen')).toBeInTheDocument();

      // First Scan → Trial Results
      await user.click(screen.getByText('Next from FirstScan'));
      expect(screen.getByTestId('trial-results-screen')).toBeInTheDocument();
    });

    it('should navigate backwards from account-creation to welcome', async () => {
      const user = userEvent.setup();
      render(<OnboardingFlow onComplete={vi.fn()} />);

      // Forward to account-creation
      await user.click(screen.getByText('Next from Welcome'));
      expect(screen.getByTestId('account-creation-screen')).toBeInTheDocument();

      // Back to welcome
      await user.click(screen.getByText('Back'));
      expect(screen.getByTestId('welcome-screen')).toBeInTheDocument();
    });

    it('should support backward navigation through all steps', async () => {
      const user = userEvent.setup();
      render(<OnboardingFlow onComplete={vi.fn()} />);

      // Navigate forward to trial-results
      await user.click(screen.getByText('Next from Welcome'));
      await user.click(screen.getByText('Next from Account'));
      await user.click(screen.getByText('Next from Mole'));
      await user.click(screen.getByText('Next from Permissions'));
      await user.click(screen.getByText('Next from Shortcut'));
      await user.click(screen.getByText('Next from FirstScan'));

      expect(screen.getByTestId('trial-results-screen')).toBeInTheDocument();

      // Navigate backward to first-scan
      await user.click(screen.getByText('Back'));
      expect(screen.getByTestId('first-scan-screen')).toBeInTheDocument();

      // Navigate backward to shortcut
      await user.click(screen.getByText('Back'));
      expect(screen.getByTestId('shortcut-screen')).toBeInTheDocument();

      // Navigate backward to permissions
      await user.click(screen.getByText('Back'));
      expect(screen.getByTestId('permissions-screen')).toBeInTheDocument();

      // Navigate backward to mole-check
      await user.click(screen.getByText('Back'));
      expect(screen.getByTestId('mole-check-screen')).toBeInTheDocument();

      // Navigate backward to account-creation
      await user.click(screen.getByText('Back'));
      expect(screen.getByTestId('account-creation-screen')).toBeInTheDocument();
    });
  });

  describe('Account Creation Screen', () => {
    it('should render account-creation screen after welcome', async () => {
      const user = userEvent.setup();
      render(<OnboardingFlow onComplete={vi.fn()} />);

      await user.click(screen.getByText('Next from Welcome'));

      expect(screen.getByTestId('account-creation-screen')).toBeInTheDocument();
    });

    it('should navigate from account-creation to mole-check', async () => {
      const user = userEvent.setup();
      render(<OnboardingFlow onComplete={vi.fn()} />);

      await user.click(screen.getByText('Next from Welcome'));
      await user.click(screen.getByText('Next from Account'));

      expect(screen.getByTestId('mole-check-screen')).toBeInTheDocument();
    });
  });

  describe('Trial Results Screen', () => {
    it('should render trial-results screen after first-scan', async () => {
      const user = userEvent.setup();
      render(<OnboardingFlow onComplete={vi.fn()} />);

      // Navigate to first-scan
      await user.click(screen.getByText('Next from Welcome'));
      await user.click(screen.getByText('Next from Account'));
      await user.click(screen.getByText('Next from Mole'));
      await user.click(screen.getByText('Next from Permissions'));
      await user.click(screen.getByText('Next from Shortcut'));

      // Navigate to trial-results
      await user.click(screen.getByText('Next from FirstScan'));

      expect(screen.getByTestId('trial-results-screen')).toBeInTheDocument();
    });

    it('should pass scan data from first-scan to trial-results', async () => {
      const user = userEvent.setup();
      render(<OnboardingFlow onComplete={vi.fn()} />);

      // Navigate to first-scan
      await user.click(screen.getByText('Next from Welcome'));
      await user.click(screen.getByText('Next from Account'));
      await user.click(screen.getByText('Next from Mole'));
      await user.click(screen.getByText('Next from Permissions'));
      await user.click(screen.getByText('Next from Shortcut'));

      // Navigate to trial-results with scan data
      await user.click(screen.getByText('Next from FirstScan'));

      // Verify scan data is passed to trial-results
      expect(screen.getByTestId('trial-metrics')).toBeInTheDocument();
      expect(screen.getByTestId('trial-disk-analysis')).toBeInTheDocument();
    });

    it('should call onComplete when navigating from trial-results', async () => {
      const user = userEvent.setup();
      const onComplete = vi.fn();
      render(<OnboardingFlow onComplete={onComplete} />);

      // Navigate through all steps
      await user.click(screen.getByText('Next from Welcome'));
      await user.click(screen.getByText('Next from Account'));
      await user.click(screen.getByText('Next from Mole'));
      await user.click(screen.getByText('Next from Permissions'));
      await user.click(screen.getByText('Next from Shortcut'));
      await user.click(screen.getByText('Next from FirstScan'));

      // Complete onboarding
      await user.click(screen.getByText('Next from Trial'));

      expect(onComplete).toHaveBeenCalledTimes(1);
    });
  });

  describe('Scan Data Persistence', () => {
    it('should preserve scan data when navigating back and forward', async () => {
      const user = userEvent.setup();
      render(<OnboardingFlow onComplete={vi.fn()} />);

      // Navigate to first-scan
      await user.click(screen.getByText('Next from Welcome'));
      await user.click(screen.getByText('Next from Account'));
      await user.click(screen.getByText('Next from Mole'));
      await user.click(screen.getByText('Next from Permissions'));
      await user.click(screen.getByText('Next from Shortcut'));

      // Navigate to trial-results with scan data
      await user.click(screen.getByText('Next from FirstScan'));

      expect(screen.getByTestId('trial-metrics')).toBeInTheDocument();
      expect(screen.getByTestId('trial-disk-analysis')).toBeInTheDocument();

      // Navigate back to first-scan
      await user.click(screen.getByText('Back'));

      // Navigate forward to trial-results again
      await user.click(screen.getByText('Next from FirstScan'));

      // Verify scan data is still present
      expect(screen.getByTestId('trial-metrics')).toBeInTheDocument();
      expect(screen.getByTestId('trial-disk-analysis')).toBeInTheDocument();
    });

    it('should handle missing scan data gracefully', async () => {
      const user = userEvent.setup();

      // Mock FirstScan to not pass data
      vi.doMock('../FirstScan', () => ({
        FirstScan: ({ onNext, onBack }: { onNext: () => void; onBack: () => void }) => (
          <div data-testid="first-scan-screen">
            <button onClick={onBack}>Back</button>
            <button onClick={() => onNext()}>Next without data</button>
          </div>
        ),
      }));

      render(<OnboardingFlow onComplete={vi.fn()} />);

      // Navigate to first-scan
      await user.click(screen.getByText('Next from Welcome'));
      await user.click(screen.getByText('Next from Account'));
      await user.click(screen.getByText('Next from Mole'));
      await user.click(screen.getByText('Next from Permissions'));
      await user.click(screen.getByText('Next from Shortcut'));

      // Navigate to trial-results without data
      await user.click(screen.getByText('Next from FirstScan'));

      // Verify trial-results renders without scan data
      expect(screen.getByTestId('trial-results-screen')).toBeInTheDocument();
      expect(screen.queryByTestId('trial-metrics')).not.toBeInTheDocument();
      expect(screen.queryByTestId('trial-disk-analysis')).not.toBeInTheDocument();
    });
  });

  describe('Step Order', () => {
    it('should include account-creation as the second step after welcome', async () => {
      const user = userEvent.setup();
      render(<OnboardingFlow onComplete={vi.fn()} />);

      await user.click(screen.getByText('Next from Welcome'));

      expect(screen.getByTestId('account-creation-screen')).toBeInTheDocument();
    });

    it('should include trial-results as the final step before completion', async () => {
      const user = userEvent.setup();
      const onComplete = vi.fn();
      render(<OnboardingFlow onComplete={onComplete} />);

      // Navigate through all steps
      await user.click(screen.getByText('Next from Welcome'));
      await user.click(screen.getByText('Next from Account'));
      await user.click(screen.getByText('Next from Mole'));
      await user.click(screen.getByText('Next from Permissions'));
      await user.click(screen.getByText('Next from Shortcut'));
      await user.click(screen.getByText('Next from FirstScan'));

      expect(screen.getByTestId('trial-results-screen')).toBeInTheDocument();

      // Verify this is the last step before completion
      await user.click(screen.getByText('Next from Trial'));
      expect(onComplete).toHaveBeenCalled();
    });

    it('should follow the complete step order', async () => {
      const user = userEvent.setup();
      render(<OnboardingFlow onComplete={vi.fn()} />);

      const expectedOrder = [
        'welcome-screen',
        'account-creation-screen',
        'mole-check-screen',
        'permissions-screen',
        'shortcut-screen',
        'first-scan-screen',
        'trial-results-screen',
      ];

      for (let i = 0; i < expectedOrder.length; i++) {
        expect(screen.getByTestId(expectedOrder[i])).toBeInTheDocument();

        // Click next button (different text for each screen)
        if (i === 0) await user.click(screen.getByText('Next from Welcome'));
        else if (i === 1) await user.click(screen.getByText('Next from Account'));
        else if (i === 2) await user.click(screen.getByText('Next from Mole'));
        else if (i === 3) await user.click(screen.getByText('Next from Permissions'));
        else if (i === 4) await user.click(screen.getByText('Next from Shortcut'));
        else if (i === 5) await user.click(screen.getByText('Next from FirstScan'));
      }
    });
  });

  describe('Edge Cases', () => {
    it('should not navigate back from welcome screen', () => {
      render(<OnboardingFlow onComplete={vi.fn()} />);

      expect(screen.getByTestId('welcome-screen')).toBeInTheDocument();
      // Welcome screen shouldn't have a Back button in the mock
      expect(screen.queryByText('Back')).not.toBeInTheDocument();
    });

    it('should complete onboarding only from trial-results screen', async () => {
      const user = userEvent.setup();
      const onComplete = vi.fn();
      render(<OnboardingFlow onComplete={onComplete} />);

      // Navigate partway through
      await user.click(screen.getByText('Next from Welcome'));
      await user.click(screen.getByText('Next from Account'));
      await user.click(screen.getByText('Next from Mole'));

      expect(onComplete).not.toHaveBeenCalled();

      // Complete full flow
      await user.click(screen.getByText('Next from Permissions'));
      await user.click(screen.getByText('Next from Shortcut'));
      await user.click(screen.getByText('Next from FirstScan'));
      await user.click(screen.getByText('Next from Trial'));

      expect(onComplete).toHaveBeenCalledTimes(1);
    });

    it('should handle rapid navigation without errors', async () => {
      const user = userEvent.setup();
      render(<OnboardingFlow onComplete={vi.fn()} />);

      // Rapidly navigate forward
      await user.click(screen.getByText('Next from Welcome'));
      await user.click(screen.getByText('Next from Account'));
      await user.click(screen.getByText('Next from Mole'));

      expect(screen.getByTestId('permissions-screen')).toBeInTheDocument();

      // Rapidly navigate backward
      await user.click(screen.getByText('Back'));
      await user.click(screen.getByText('Back'));

      expect(screen.getByTestId('account-creation-screen')).toBeInTheDocument();
    });
  });
});
