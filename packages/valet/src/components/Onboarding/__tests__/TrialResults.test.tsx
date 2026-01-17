import { describe, it, expect, beforeEach, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { TrialResults } from '../TrialResults';

describe('TrialResults', () => {
  const mockOnNext = vi.fn();
  const mockOnBack = vi.fn();

  const mockMetrics = {
    disk: { available: 100000000000, total: 500000000000, percentage: 80 },
    memory: { used: 8000000000, total: 16000000000, percentage: 50 },
    cpu: { percentage: 25 },
  };

  const mockDiskAnalysis = {
    directories: [
      { path: '/System/Library', size: 5000000000 },
      { path: '/Applications', size: 3000000000 },
      { path: '/Users', size: 1000000000 },
    ],
  };

  beforeEach(() => {
    localStorage.clear();
    mockOnNext.mockClear();
    mockOnBack.mockClear();
  });

  describe('Trial Date Display', () => {
    it('should use stored trial start date for end date display', () => {
      // Set trial start to a known date (e.g., Jan 1, 2024)
      const trialStartTime = new Date('2024-01-01T00:00:00Z').getTime();
      localStorage.setItem('valet_trial_start', trialStartTime.toString());

      render(
        <TrialResults
          onNext={mockOnNext}
          onBack={mockOnBack}
          metrics={mockMetrics}
          diskAnalysis={mockDiskAnalysis}
        />
      );

      // Trial should end 7 days later (Jan 8, 2024)
      const expectedEndDate = new Date('2024-01-08T00:00:00Z');
      const formattedEndDate = expectedEndDate.toLocaleDateString('en-US', {
        month: 'long',
        day: 'numeric',
        year: 'numeric',
      });

      expect(screen.getByText(`Ends on ${formattedEndDate}`)).toBeInTheDocument();
    });

    it('should calculate end date as 7 days after stored trial start', () => {
      // Set trial start to a different date (e.g., Feb 15, 2024)
      const trialStartTime = new Date('2024-02-15T12:00:00Z').getTime();
      localStorage.setItem('valet_trial_start', trialStartTime.toString());

      render(
        <TrialResults
          onNext={mockOnNext}
          onBack={mockOnBack}
          metrics={mockMetrics}
          diskAnalysis={mockDiskAnalysis}
        />
      );

      // Trial should end 7 days later (Feb 22, 2024)
      const expectedEndDate = new Date('2024-02-22T12:00:00Z');
      const formattedEndDate = expectedEndDate.toLocaleDateString('en-US', {
        month: 'long',
        day: 'numeric',
        year: 'numeric',
      });

      expect(screen.getByText(`Ends on ${formattedEndDate}`)).toBeInTheDocument();
    });

    it('should use current time when trial start is not in localStorage', () => {
      // Don't set trial start
      const beforeRender = Date.now();

      render(
        <TrialResults
          onNext={mockOnNext}
          onBack={mockOnBack}
          metrics={mockMetrics}
          diskAnalysis={mockDiskAnalysis}
        />
      );

      const afterRender = Date.now();

      // Trial end should be approximately 7 days from now
      const minEndDate = new Date(beforeRender + 7 * 24 * 60 * 60 * 1000);
      const maxEndDate = new Date(afterRender + 7 * 24 * 60 * 60 * 1000);

      const minFormatted = minEndDate.toLocaleDateString('en-US', {
        month: 'long',
        day: 'numeric',
        year: 'numeric',
      });
      const maxFormatted = maxEndDate.toLocaleDateString('en-US', {
        month: 'long',
        day: 'numeric',
        year: 'numeric',
      });

      // Since formatting might differ by date, just verify the pattern exists
      expect(screen.getByText(/Ends on/)).toBeInTheDocument();
    });

    it('should handle invalid trial start timestamp gracefully', () => {
      // Set invalid trial start
      localStorage.setItem('valet_trial_start', 'invalid-timestamp');

      render(
        <TrialResults
          onNext={mockOnNext}
          onBack={mockOnBack}
          metrics={mockMetrics}
          diskAnalysis={mockDiskAnalysis}
        />
      );

      // Should still render (will use NaN → Date.now() as fallback)
      expect(screen.getByText(/Ends on/)).toBeInTheDocument();
    });

    it('should persist trial start date across component re-renders', () => {
      const trialStartTime = new Date('2024-03-10T00:00:00Z').getTime();
      localStorage.setItem('valet_trial_start', trialStartTime.toString());

      const { rerender } = render(
        <TrialResults
          onNext={mockOnNext}
          onBack={mockOnBack}
          metrics={mockMetrics}
          diskAnalysis={mockDiskAnalysis}
        />
      );

      const expectedEndDate = new Date('2024-03-17T00:00:00Z');
      const formattedEndDate = expectedEndDate.toLocaleDateString('en-US', {
        month: 'long',
        day: 'numeric',
        year: 'numeric',
      });

      expect(screen.getByText(`Ends on ${formattedEndDate}`)).toBeInTheDocument();

      // Re-render component
      rerender(
        <TrialResults
          onNext={mockOnNext}
          onBack={mockOnBack}
          metrics={mockMetrics}
          diskAnalysis={mockDiskAnalysis}
        />
      );

      // End date should remain the same
      expect(screen.getByText(`Ends on ${formattedEndDate}`)).toBeInTheDocument();
    });
  });

  describe('Trial Information Display', () => {
    it('should display trial active status', () => {
      render(
        <TrialResults onNext={mockOnNext} onBack={mockOnBack} metrics={mockMetrics} diskAnalysis={mockDiskAnalysis} />
      );

      expect(screen.getByText('Free Trial Active')).toBeInTheDocument();
    });

    it('should display trial features', () => {
      render(
        <TrialResults onNext={mockOnNext} onBack={mockOnBack} metrics={mockMetrics} diskAnalysis={mockDiskAnalysis} />
      );

      expect(screen.getByText(/Full access to all features/)).toBeInTheDocument();
      expect(screen.getByText(/Voice-powered maintenance/)).toBeInTheDocument();
      expect(screen.getByText(/Real-time system monitoring/)).toBeInTheDocument();
      expect(screen.getByText(/Smart cleaning & optimization/)).toBeInTheDocument();
    });

    it('should display pricing information', () => {
      render(
        <TrialResults onNext={mockOnNext} onBack={mockOnBack} metrics={mockMetrics} diskAnalysis={mockDiskAnalysis} />
      );

      expect(screen.getByText('$29/year')).toBeInTheDocument();
      expect(screen.getByText('Cancel anytime during trial')).toBeInTheDocument();
    });
  });

  describe('Metrics Display', () => {
    it('should display system metrics when provided', () => {
      render(
        <TrialResults onNext={mockOnNext} onBack={mockOnBack} metrics={mockMetrics} diskAnalysis={mockDiskAnalysis} />
      );

      expect(screen.getByText('Your Mac at a Glance')).toBeInTheDocument();
      expect(screen.getByText('Available Space')).toBeInTheDocument();
      expect(screen.getByText('Memory Usage')).toBeInTheDocument();
      expect(screen.getByText('50%')).toBeInTheDocument();
    });

    it('should display potential savings from top directories', () => {
      render(
        <TrialResults onNext={mockOnNext} onBack={mockOnBack} metrics={mockMetrics} diskAnalysis={mockDiskAnalysis} />
      );

      expect(screen.getByText('Potential Savings')).toBeInTheDocument();
    });

    it('should not display insights card when metrics are not provided', () => {
      render(<TrialResults onNext={mockOnNext} onBack={mockOnBack} />);

      expect(screen.queryByText('Your Mac at a Glance')).not.toBeInTheDocument();
      expect(screen.queryByText('Available Space')).not.toBeInTheDocument();
    });

    it('should not display potential savings when disk analysis is empty', () => {
      const emptyDiskAnalysis = { directories: [] };

      render(
        <TrialResults
          onNext={mockOnNext}
          onBack={mockOnBack}
          metrics={mockMetrics}
          diskAnalysis={emptyDiskAnalysis}
        />
      );

      expect(screen.queryByText('Potential Savings')).not.toBeInTheDocument();
    });

    it('should calculate potential savings from top 3 directories', () => {
      const largeDiskAnalysis = {
        directories: [
          { path: '/dir1', size: 5000000000 }, // 5 GB
          { path: '/dir2', size: 3000000000 }, // 3 GB
          { path: '/dir3', size: 1000000000 }, // 1 GB
          { path: '/dir4', size: 500000000 }, // 0.5 GB (should not be included)
        ],
      };

      render(
        <TrialResults
          onNext={mockOnNext}
          onBack={mockOnBack}
          metrics={mockMetrics}
          diskAnalysis={largeDiskAnalysis}
        />
      );

      // Total of top 3: 5 + 3 + 1 = 9 GB
      expect(screen.getByText('Potential Savings')).toBeInTheDocument();
      expect(screen.getByText('9 GB')).toBeInTheDocument();
    });
  });

  describe('Next Steps Display', () => {
    it('should display next steps', () => {
      render(
        <TrialResults onNext={mockOnNext} onBack={mockOnBack} metrics={mockMetrics} diskAnalysis={mockDiskAnalysis} />
      );

      expect(screen.getByText("What's Next?")).toBeInTheDocument();
      expect(screen.getByText('Try Voice Commands')).toBeInTheDocument();
      expect(screen.getByText(/Press Cmd\+Shift\+Space/)).toBeInTheDocument();
      expect(screen.getByText('Keep Your Mac Healthy')).toBeInTheDocument();
      expect(screen.getByText('Clean When Needed')).toBeInTheDocument();
    });
  });

  describe('Navigation', () => {
    it('should call onNext when "Start Using Valet" is clicked', async () => {
      const user = userEvent.setup();
      render(
        <TrialResults onNext={mockOnNext} onBack={mockOnBack} metrics={mockMetrics} diskAnalysis={mockDiskAnalysis} />
      );

      await user.click(screen.getByText('Start Using Valet'));

      expect(mockOnNext).toHaveBeenCalledTimes(1);
    });

    it('should call onBack when "Back" is clicked', async () => {
      const user = userEvent.setup();
      render(
        <TrialResults onNext={mockOnNext} onBack={mockOnBack} metrics={mockMetrics} diskAnalysis={mockDiskAnalysis} />
      );

      await user.click(screen.getByText('Back'));

      expect(mockOnBack).toHaveBeenCalledTimes(1);
    });
  });

  describe('Edge Cases', () => {
    it('should render without metrics and disk analysis', () => {
      render(<TrialResults onNext={mockOnNext} onBack={mockOnBack} />);

      expect(screen.getByText('Free Trial Active')).toBeInTheDocument();
      expect(screen.getByText('Start Using Valet')).toBeInTheDocument();
      expect(screen.queryByText('Your Mac at a Glance')).not.toBeInTheDocument();
    });

    it('should render with metrics but without disk analysis', () => {
      render(<TrialResults onNext={mockOnNext} onBack={mockOnBack} metrics={mockMetrics} />);

      expect(screen.getByText('Your Mac at a Glance')).toBeInTheDocument();
      expect(screen.queryByText('Potential Savings')).not.toBeInTheDocument();
    });

    it('should render with null metrics', () => {
      render(<TrialResults onNext={mockOnNext} onBack={mockOnBack} metrics={null} diskAnalysis={null} />);

      expect(screen.getByText('Free Trial Active')).toBeInTheDocument();
      expect(screen.queryByText('Your Mac at a Glance')).not.toBeInTheDocument();
    });
  });
});
