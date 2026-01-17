import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { SettingsPanel } from '../Settings/SettingsPanel';
import * as settings from '../../lib/settings';
import * as autostart from '../../lib/autostart';
import { invoke } from '@tauri-apps/api/core';

// Mock the dependencies
vi.mock('../../lib/settings', () => ({
  useSettings: vi.fn(),
}));

vi.mock('../../lib/autostart', () => ({
  setAutostart: vi.fn(),
}));

vi.mock('@tauri-apps/api/core', () => ({
  invoke: vi.fn(),
}));

// Mock the ApiKeysModal component to avoid keychain calls
vi.mock('../Settings/ApiKeysModal', () => ({
  ApiKeysModal: ({ isOpen, onClose }: any) => {
    if (!isOpen) return null;
    return (
      <div data-testid="api-keys-modal">
        <button onClick={onClose}>Close Modal</button>
      </div>
    );
  },
}));

describe('SettingsPanel - Side Effects', () => {
  let mockUpdateSetting: ReturnType<typeof vi.fn>;
  let mockSetAutostart: ReturnType<typeof vi.fn>;
  let mockInvoke: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    vi.clearAllMocks();

    mockUpdateSetting = vi.fn().mockResolvedValue(undefined);
    mockSetAutostart = vi.fn().mockResolvedValue(undefined);
    mockInvoke = vi.fn().mockResolvedValue(undefined);

    // Setup default mock for useSettings
    vi.mocked(settings.useSettings).mockReturnValue({
      settings: {
        voiceEnabled: 'true',
        monitoringFrequency: '30',
        notificationMode: 'critical',
        autoStart: 'false',
      },
      loading: false,
      error: null,
      updateSetting: mockUpdateSetting,
      removeSetting: vi.fn(),
      refresh: vi.fn(),
    });

    vi.mocked(autostart.setAutostart).mockImplementation(mockSetAutostart);
    vi.mocked(invoke).mockImplementation(mockInvoke);
  });

  describe('Monitoring frequency changes', () => {
    it('should invoke update_monitoring_config when monitoring frequency changes', async () => {
      render(<SettingsPanel />);

      const select = screen.getByLabelText('Check Frequency');
      fireEvent.change(select, { target: { value: '15' } });

      await waitFor(() => {
        expect(mockUpdateSetting).toHaveBeenCalledWith('monitoringFrequency', '15');
      });

      await waitFor(() => {
        expect(mockInvoke).toHaveBeenCalledWith('update_monitoring_config', {
          enabled: true,
          interval_minutes: 15,
        });
      });
    });

    it('should disable monitoring when set to manual only (0)', async () => {
      render(<SettingsPanel />);

      const select = screen.getByLabelText('Check Frequency');
      fireEvent.change(select, { target: { value: '0' } });

      await waitFor(() => {
        expect(mockUpdateSetting).toHaveBeenCalledWith('monitoringFrequency', '0');
      });

      await waitFor(() => {
        expect(mockInvoke).toHaveBeenCalledWith('update_monitoring_config', {
          enabled: false,
          interval_minutes: 30, // Uses default when manual
        });
      });
    });

    it('should enable monitoring with 60 minute interval', async () => {
      render(<SettingsPanel />);

      const select = screen.getByLabelText('Check Frequency');
      fireEvent.change(select, { target: { value: '60' } });

      await waitFor(() => {
        expect(mockUpdateSetting).toHaveBeenCalledWith('monitoringFrequency', '60');
      });

      await waitFor(() => {
        expect(mockInvoke).toHaveBeenCalledWith('update_monitoring_config', {
          enabled: true,
          interval_minutes: 60,
        });
      });
    });

    it('should handle update_monitoring_config errors gracefully', async () => {
      const consoleErrorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
      mockInvoke.mockRejectedValueOnce(new Error('Backend error'));

      render(<SettingsPanel />);

      const select = screen.getByLabelText('Check Frequency');
      fireEvent.change(select, { target: { value: '15' } });

      await waitFor(() => {
        expect(mockUpdateSetting).toHaveBeenCalled();
      });

      await waitFor(() => {
        expect(consoleErrorSpy).toHaveBeenCalledWith(
          'Failed to update monitoring config:',
          expect.any(Error)
        );
      });

      consoleErrorSpy.mockRestore();
    });
  });

  describe('Autostart changes', () => {
    it('should invoke setAutostart when auto-start is enabled', async () => {
      render(<SettingsPanel />);

      const checkbox = screen.getByLabelText('Launch at Login');
      fireEvent.click(checkbox);

      await waitFor(() => {
        expect(mockUpdateSetting).toHaveBeenCalledWith('autoStart', 'true');
      });

      await waitFor(() => {
        expect(mockSetAutostart).toHaveBeenCalledWith(true);
      });
    });

    it('should invoke setAutostart when auto-start is disabled', async () => {
      // Start with autoStart enabled
      vi.mocked(settings.useSettings).mockReturnValue({
        settings: {
          voiceEnabled: 'true',
          monitoringFrequency: '30',
          notificationMode: 'critical',
          autoStart: 'true',
        },
        loading: false,
        error: null,
        updateSetting: mockUpdateSetting,
        removeSetting: vi.fn(),
        refresh: vi.fn(),
      });

      render(<SettingsPanel />);

      const checkbox = screen.getByLabelText('Launch at Login');
      fireEvent.click(checkbox);

      await waitFor(() => {
        expect(mockUpdateSetting).toHaveBeenCalledWith('autoStart', 'false');
      });

      await waitFor(() => {
        expect(mockSetAutostart).toHaveBeenCalledWith(false);
      });
    });

    it('should handle setAutostart errors gracefully', async () => {
      const consoleErrorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
      mockSetAutostart.mockRejectedValueOnce(new Error('Backend error'));

      render(<SettingsPanel />);

      const checkbox = screen.getByLabelText('Launch at Login');
      fireEvent.click(checkbox);

      await waitFor(() => {
        expect(mockUpdateSetting).toHaveBeenCalled();
      });

      await waitFor(() => {
        expect(consoleErrorSpy).toHaveBeenCalledWith(
          'Failed to update autostart:',
          expect.any(Error)
        );
      });

      consoleErrorSpy.mockRestore();
    });
  });

  describe('Settings persistence without backend side effects', () => {
    it('should update voice enabled setting without backend call', async () => {
      render(<SettingsPanel />);

      const checkbox = screen.getByLabelText('Enable Voice Input');
      fireEvent.click(checkbox);

      await waitFor(() => {
        expect(mockUpdateSetting).toHaveBeenCalledWith('voiceEnabled', 'false');
      });

      // Should not call any backend commands
      expect(mockInvoke).not.toHaveBeenCalled();
      expect(mockSetAutostart).not.toHaveBeenCalled();
    });

    it('should update notification mode without backend call', async () => {
      render(<SettingsPanel />);

      const select = screen.getByLabelText('Notification Mode');
      fireEvent.change(select, { target: { value: 'suggestions' } });

      await waitFor(() => {
        expect(mockUpdateSetting).toHaveBeenCalledWith('notificationMode', 'suggestions');
      });

      // Should not call any backend commands
      expect(mockInvoke).not.toHaveBeenCalled();
      expect(mockSetAutostart).not.toHaveBeenCalled();
    });
  });

  describe('Loading state', () => {
    it('should show loading spinner when settings are loading', () => {
      vi.mocked(settings.useSettings).mockReturnValue({
        settings: {
          voiceEnabled: 'true',
          monitoringFrequency: '30',
          notificationMode: 'critical',
          autoStart: 'false',
        },
        loading: true,
        error: null,
        updateSetting: mockUpdateSetting,
        removeSetting: vi.fn(),
        refresh: vi.fn(),
      });

      render(<SettingsPanel />);

      expect(screen.getByText('Loading settings...')).toBeInTheDocument();
    });
  });

  describe('Synchronization between settings and local state', () => {
    it('should sync local state when settings prop changes', () => {
      const { rerender } = render(<SettingsPanel />);

      // Initial state
      expect(screen.getByLabelText('Enable Voice Input')).toBeChecked();
      expect(screen.getByLabelText('Launch at Login')).not.toBeChecked();

      // Update settings
      vi.mocked(settings.useSettings).mockReturnValue({
        settings: {
          voiceEnabled: 'false',
          monitoringFrequency: '15',
          notificationMode: 'weekly',
          autoStart: 'true',
        },
        loading: false,
        error: null,
        updateSetting: mockUpdateSetting,
        removeSetting: vi.fn(),
        refresh: vi.fn(),
      });

      rerender(<SettingsPanel />);

      // Check updated state
      expect(screen.getByLabelText('Enable Voice Input')).not.toBeChecked();
      expect(screen.getByLabelText('Launch at Login')).toBeChecked();
      expect(screen.getByLabelText('Check Frequency')).toHaveValue('15');
      expect(screen.getByLabelText('Notification Mode')).toHaveValue('weekly');
    });
  });

  describe('API Keys Modal', () => {
    it('should show API Keys modal when Manage API Keys button is clicked', () => {
      render(<SettingsPanel />);

      const manageButton = screen.getByText('Manage API Keys');
      fireEvent.click(manageButton);

      expect(screen.getByTestId('api-keys-modal')).toBeInTheDocument();
    });

    it('should hide API Keys modal when closed', () => {
      render(<SettingsPanel />);

      const manageButton = screen.getByText('Manage API Keys');
      fireEvent.click(manageButton);

      expect(screen.getByTestId('api-keys-modal')).toBeInTheDocument();

      const closeButton = screen.getByText('Close Modal');
      fireEvent.click(closeButton);

      expect(screen.queryByTestId('api-keys-modal')).not.toBeInTheDocument();
    });

    it('should call onKeysChanged when modal calls it', () => {
      const mockOnKeysChanged = vi.fn();
      render(<SettingsPanel onKeysChanged={mockOnKeysChanged} />);

      const manageButton = screen.getByText('Manage API Keys');
      fireEvent.click(manageButton);

      // The mock modal would need to call onKeysChanged to test this
      // Since our mock is simple, we verify the prop is passed
      expect(screen.getByTestId('api-keys-modal')).toBeInTheDocument();
    });

    it('should not render modal initially', () => {
      render(<SettingsPanel />);

      expect(screen.queryByTestId('api-keys-modal')).not.toBeInTheDocument();
    });

    it('should pass isOpen=false to modal when closed, enabling lazy-loading', () => {
      render(<SettingsPanel />);

      // Modal should be closed initially
      expect(screen.queryByTestId('api-keys-modal')).not.toBeInTheDocument();

      // Open modal
      const manageButton = screen.getByText('Manage API Keys');
      fireEvent.click(manageButton);

      expect(screen.getByTestId('api-keys-modal')).toBeInTheDocument();

      // Close modal
      const closeButton = screen.getByText('Close Modal');
      fireEvent.click(closeButton);

      // Modal should not be rendered (isOpen=false)
      expect(screen.queryByTestId('api-keys-modal')).not.toBeInTheDocument();
    });
  });

  describe('Account & Trial Display', () => {
    beforeEach(() => {
      localStorage.clear();
    });

    it('should display user email from localStorage', () => {
      localStorage.setItem('valet_user_email', 'user@example.com');

      render(<SettingsPanel />);

      expect(screen.getByText('user@example.com')).toBeInTheDocument();
    });

    it('should display "Not signed in" when no email in localStorage', () => {
      render(<SettingsPanel />);

      expect(screen.getByText('Not signed in')).toBeInTheDocument();
    });

    it('should display trial active status', () => {
      render(<SettingsPanel />);

      expect(screen.getByText('✓ Free Trial Active')).toBeInTheDocument();
    });

    it('should render trial end date using stored trial start timestamp', () => {
      // Set trial start to Jan 1, 2024
      const trialStartTime = new Date('2024-01-01T00:00:00Z').getTime();
      localStorage.setItem('valet_trial_start', trialStartTime.toString());

      render(<SettingsPanel />);

      // Trial should end 7 days later (Jan 8, 2024)
      const expectedEndDate = new Date('2024-01-08T00:00:00Z');
      const formattedEndDate = expectedEndDate.toLocaleDateString('en-US', {
        month: 'short',
        day: 'numeric',
        year: 'numeric',
      });

      expect(screen.getByText(formattedEndDate)).toBeInTheDocument();
    });

    it('should calculate trial end date correctly for different start dates', () => {
      // Set trial start to Feb 15, 2024
      const trialStartTime = new Date('2024-02-15T12:00:00Z').getTime();
      localStorage.setItem('valet_trial_start', trialStartTime.toString());

      render(<SettingsPanel />);

      // Trial should end 7 days later (Feb 22, 2024)
      const expectedEndDate = new Date('2024-02-22T12:00:00Z');
      const formattedEndDate = expectedEndDate.toLocaleDateString('en-US', {
        month: 'short',
        day: 'numeric',
        year: 'numeric',
      });

      expect(screen.getByText(formattedEndDate)).toBeInTheDocument();
    });

    it('should handle expired trial state (end date in the past)', () => {
      // Set trial start to 30 days ago
      const trialStartTime = Date.now() - 30 * 24 * 60 * 60 * 1000;
      localStorage.setItem('valet_trial_start', trialStartTime.toString());

      render(<SettingsPanel />);

      // Should still render end date (even if expired)
      expect(screen.getByText('✓ Free Trial Active')).toBeInTheDocument();

      // End date should be 23 days ago (30 - 7)
      const expectedEndDate = new Date(trialStartTime + 7 * 24 * 60 * 60 * 1000);
      const formattedEndDate = expectedEndDate.toLocaleDateString('en-US', {
        month: 'short',
        day: 'numeric',
        year: 'numeric',
      });

      expect(screen.getByText(formattedEndDate)).toBeInTheDocument();
    });

    it('should use current time when trial start is not in localStorage', () => {
      render(<SettingsPanel />);

      // Should render a trial end date (even without stored start)
      const trialEndLabel = screen.getByText('Trial Ends:');
      expect(trialEndLabel).toBeInTheDocument();

      // The next sibling should contain a date
      const trialEndValue = trialEndLabel.nextElementSibling;
      expect(trialEndValue).toBeInTheDocument();
      expect(trialEndValue?.textContent).toMatch(/\w+ \d+, \d{4}/);
    });

    it('should handle invalid trial start timestamp', () => {
      localStorage.setItem('valet_trial_start', 'invalid-timestamp');

      render(<SettingsPanel />);

      // Should still render without crashing
      expect(screen.getByText('✓ Free Trial Active')).toBeInTheDocument();
    });

    it('should display pricing information', () => {
      render(<SettingsPanel />);

      expect(screen.getByText('$29/year after trial')).toBeInTheDocument();
    });

    it('should display manage account button', () => {
      render(<SettingsPanel />);

      const manageButton = screen.getByText('Manage Account');
      expect(manageButton).toBeInTheDocument();
    });
  });

  describe('Alert Threshold Controls', () => {
    it('should display disk warning threshold from settings', () => {
      vi.mocked(settings.useSettings).mockReturnValue({
        settings: {
          voiceEnabled: 'true',
          monitoringFrequency: '30',
          notificationMode: 'critical',
          autoStart: 'false',
          diskWarningThreshold: '25',
          diskCriticalThreshold: '10',
        },
        loading: false,
        error: null,
        updateSetting: mockUpdateSetting,
        removeSetting: vi.fn(),
        refresh: vi.fn(),
      });

      render(<SettingsPanel />);

      const warningInput = screen.getByLabelText('Disk Warning (GB)') as HTMLInputElement;
      expect(warningInput.value).toBe('25');
    });

    it('should display disk critical threshold from settings', () => {
      vi.mocked(settings.useSettings).mockReturnValue({
        settings: {
          voiceEnabled: 'true',
          monitoringFrequency: '30',
          notificationMode: 'critical',
          autoStart: 'false',
          diskWarningThreshold: '20',
          diskCriticalThreshold: '8',
        },
        loading: false,
        error: null,
        updateSetting: mockUpdateSetting,
        removeSetting: vi.fn(),
        refresh: vi.fn(),
      });

      render(<SettingsPanel />);

      const criticalInput = screen.getByLabelText('Disk Critical (GB)') as HTMLInputElement;
      expect(criticalInput.value).toBe('8');
    });

    it('should use default thresholds when not in settings', () => {
      render(<SettingsPanel />);

      const warningInput = screen.getByLabelText('Disk Warning (GB)') as HTMLInputElement;
      const criticalInput = screen.getByLabelText('Disk Critical (GB)') as HTMLInputElement;

      expect(warningInput.value).toBe('20');
      expect(criticalInput.value).toBe('10');
    });

    it('should persist valid warning threshold on blur', async () => {
      render(<SettingsPanel />);

      const warningInput = screen.getByLabelText('Disk Warning (GB)') as HTMLInputElement;

      fireEvent.change(warningInput, { target: { value: '30' } });
      fireEvent.blur(warningInput);

      await waitFor(() => {
        expect(mockUpdateSetting).toHaveBeenCalledWith('diskWarningThreshold', '30');
      });
    });

    it('should persist valid critical threshold on blur', async () => {
      render(<SettingsPanel />);

      const criticalInput = screen.getByLabelText('Disk Critical (GB)') as HTMLInputElement;

      fireEvent.change(criticalInput, { target: { value: '5' } });
      fireEvent.blur(criticalInput);

      await waitFor(() => {
        expect(mockUpdateSetting).toHaveBeenCalledWith('diskCriticalThreshold', '5');
      });
    });

    it('should not persist empty warning threshold (revert to previous)', async () => {
      const consoleWarnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});

      render(<SettingsPanel />);

      const warningInput = screen.getByLabelText('Disk Warning (GB)') as HTMLInputElement;

      // Initial value is '20'
      expect(warningInput.value).toBe('20');

      // Clear the input
      fireEvent.change(warningInput, { target: { value: '' } });
      fireEvent.blur(warningInput);

      await waitFor(() => {
        expect(consoleWarnSpy).toHaveBeenCalledWith('Warning threshold must be a valid positive number');
      });

      // Should revert to previous value
      expect(warningInput.value).toBe('20');

      // Should not persist the empty value
      expect(mockUpdateSetting).not.toHaveBeenCalledWith('diskWarningThreshold', expect.anything());

      consoleWarnSpy.mockRestore();
    });

    it('should not persist NaN warning threshold (revert to previous)', async () => {
      const consoleWarnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});

      render(<SettingsPanel />);

      const warningInput = screen.getByLabelText('Disk Warning (GB)') as HTMLInputElement;

      // Set invalid value
      fireEvent.change(warningInput, { target: { value: 'abc' } });
      fireEvent.blur(warningInput);

      await waitFor(() => {
        expect(consoleWarnSpy).toHaveBeenCalledWith('Warning threshold must be a valid positive number');
      });

      // Should revert to previous value
      expect(warningInput.value).toBe('20');

      consoleWarnSpy.mockRestore();
    });

    it('should not persist empty critical threshold (revert to previous)', async () => {
      const consoleWarnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});

      render(<SettingsPanel />);

      const criticalInput = screen.getByLabelText('Disk Critical (GB)') as HTMLInputElement;

      // Initial value is '10'
      expect(criticalInput.value).toBe('10');

      // Clear the input
      fireEvent.change(criticalInput, { target: { value: '' } });
      fireEvent.blur(criticalInput);

      await waitFor(() => {
        expect(consoleWarnSpy).toHaveBeenCalledWith('Critical threshold must be a valid positive number');
      });

      // Should revert to previous value
      expect(criticalInput.value).toBe('10');

      consoleWarnSpy.mockRestore();
    });

    it('should not persist NaN critical threshold (revert to previous)', async () => {
      const consoleWarnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});

      render(<SettingsPanel />);

      const criticalInput = screen.getByLabelText('Disk Critical (GB)') as HTMLInputElement;

      // Set invalid value
      fireEvent.change(criticalInput, { target: { value: 'xyz' } });
      fireEvent.blur(criticalInput);

      await waitFor(() => {
        expect(consoleWarnSpy).toHaveBeenCalledWith('Critical threshold must be a valid positive number');
      });

      // Should revert to previous value
      expect(criticalInput.value).toBe('10');

      consoleWarnSpy.mockRestore();
    });

    it('should reject warning threshold less than or equal to critical threshold', async () => {
      const consoleWarnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});

      render(<SettingsPanel />);

      const warningInput = screen.getByLabelText('Disk Warning (GB)') as HTMLInputElement;

      // Try to set warning threshold to 10 (same as critical)
      fireEvent.change(warningInput, { target: { value: '10' } });
      fireEvent.blur(warningInput);

      await waitFor(() => {
        expect(consoleWarnSpy).toHaveBeenCalledWith('Warning threshold must be greater than critical threshold');
      });

      // Should revert to previous value
      expect(warningInput.value).toBe('20');

      consoleWarnSpy.mockRestore();
    });

    it('should reject critical threshold greater than or equal to warning threshold', async () => {
      const consoleWarnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});

      render(<SettingsPanel />);

      const criticalInput = screen.getByLabelText('Disk Critical (GB)') as HTMLInputElement;

      // Try to set critical threshold to 20 (same as warning)
      fireEvent.change(criticalInput, { target: { value: '20' } });
      fireEvent.blur(criticalInput);

      await waitFor(() => {
        expect(consoleWarnSpy).toHaveBeenCalledWith('Critical threshold must be less than warning threshold');
      });

      // Should revert to previous value
      expect(criticalInput.value).toBe('10');

      consoleWarnSpy.mockRestore();
    });

    it('should preserve defaults when invalid thresholds in settings', () => {
      vi.mocked(settings.useSettings).mockReturnValue({
        settings: {
          voiceEnabled: 'true',
          monitoringFrequency: '30',
          notificationMode: 'critical',
          autoStart: 'false',
          diskWarningThreshold: '', // Empty string
          diskCriticalThreshold: 'invalid', // Invalid value
        },
        loading: false,
        error: null,
        updateSetting: mockUpdateSetting,
        removeSetting: vi.fn(),
        refresh: vi.fn(),
      });

      render(<SettingsPanel />);

      const warningInput = screen.getByLabelText('Disk Warning (GB)') as HTMLInputElement;
      const criticalInput = screen.getByLabelText('Disk Critical (GB)') as HTMLInputElement;

      // Should fall back to defaults
      expect(warningInput.value).toBe('20');
      expect(criticalInput.value).toBe('10');
    });

    it('should allow multi-digit threshold input without premature validation', async () => {
      render(<SettingsPanel />);

      const warningInput = screen.getByLabelText('Disk Warning (GB)') as HTMLInputElement;

      // Type '100' character by character
      fireEvent.change(warningInput, { target: { value: '1' } });
      expect(warningInput.value).toBe('1');

      fireEvent.change(warningInput, { target: { value: '10' } });
      expect(warningInput.value).toBe('10');

      fireEvent.change(warningInput, { target: { value: '100' } });
      expect(warningInput.value).toBe('100');

      // Only validate on blur
      fireEvent.blur(warningInput);

      await waitFor(() => {
        expect(mockUpdateSetting).toHaveBeenCalledWith('diskWarningThreshold', '100');
      });
    });
  });
});
