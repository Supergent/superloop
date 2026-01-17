import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { ApiKeysModal } from '../Settings/ApiKeysModal';
import * as useApiKeysHook from '../../hooks/useApiKeys';

// Mock the useApiKeys hook
vi.mock('../../hooks/useApiKeys', () => ({
  useApiKeys: vi.fn(),
}));

describe('ApiKeysModal', () => {
  let mockSaveKey: ReturnType<typeof vi.fn>;
  let mockRemoveKey: ReturnType<typeof vi.fn>;
  let mockOnClose: ReturnType<typeof vi.fn>;
  let mockOnKeysChanged: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    vi.clearAllMocks();

    mockSaveKey = vi.fn().mockResolvedValue(undefined);
    mockRemoveKey = vi.fn().mockResolvedValue(undefined);
    mockOnClose = vi.fn();
    mockOnKeysChanged = vi.fn();

    // Setup default mock for useApiKeys
    vi.mocked(useApiKeysHook.useApiKeys).mockReturnValue({
      keys: {
        assemblyAi: null,
        vapiPublic: null,
        llmProxy: null,
      },
      status: {
        assemblyAi: false,
        vapiPublic: false,
        llmProxy: false,
      },
      loading: false,
      error: null,
      loadKeys: vi.fn().mockResolvedValue(undefined),
      saveKey: mockSaveKey,
      removeKey: mockRemoveKey,
      refreshStatus: vi.fn().mockResolvedValue(undefined),
    });
  });

  describe('Modal rendering', () => {
    it('should not render when closed', () => {
      render(
        <ApiKeysModal
          isOpen={false}
          onClose={mockOnClose}
          onKeysChanged={mockOnKeysChanged}
        />
      );

      expect(screen.queryByText('Manage API Keys')).not.toBeInTheDocument();
    });

    it('should render when open', () => {
      render(
        <ApiKeysModal
          isOpen={true}
          onClose={mockOnClose}
          onKeysChanged={mockOnKeysChanged}
        />
      );

      expect(screen.getByText('Manage API Keys')).toBeInTheDocument();
      expect(screen.getByText('AssemblyAI API Key')).toBeInTheDocument();
      expect(screen.getByText('Vapi Public Key')).toBeInTheDocument();
      expect(screen.getByText('LLM Proxy API Key')).toBeInTheDocument();
    });

    it('should show info message about keychain storage', () => {
      render(
        <ApiKeysModal
          isOpen={true}
          onClose={mockOnClose}
          onKeysChanged={mockOnKeysChanged}
        />
      );

      expect(
        screen.getByText(/API keys are stored securely in your macOS Keychain/i)
      ).toBeInTheDocument();
    });

    it('should pass enabled flag to useApiKeys based on isOpen', () => {
      const { rerender } = render(
        <ApiKeysModal
          isOpen={false}
          onClose={mockOnClose}
          onKeysChanged={mockOnKeysChanged}
        />
      );

      expect(useApiKeysHook.useApiKeys).toHaveBeenCalledWith({ enabled: false });

      rerender(
        <ApiKeysModal
          isOpen={true}
          onClose={mockOnClose}
          onKeysChanged={mockOnKeysChanged}
        />
      );

      expect(useApiKeysHook.useApiKeys).toHaveBeenCalledWith({ enabled: true });
    });
  });

  describe('Closing modal', () => {
    it('should call onClose when close button is clicked', () => {
      render(
        <ApiKeysModal
          isOpen={true}
          onClose={mockOnClose}
          onKeysChanged={mockOnKeysChanged}
        />
      );

      const closeButton = screen.getByRole('button', { name: '✕' });
      fireEvent.click(closeButton);

      expect(mockOnClose).toHaveBeenCalledTimes(1);
    });

    it('should call onClose when Close footer button is clicked', () => {
      render(
        <ApiKeysModal
          isOpen={true}
          onClose={mockOnClose}
          onKeysChanged={mockOnKeysChanged}
        />
      );

      const closeButton = screen.getByRole('button', { name: 'Close' });
      fireEvent.click(closeButton);

      expect(mockOnClose).toHaveBeenCalledTimes(1);
    });

    it('should call onClose when overlay is clicked', () => {
      render(
        <ApiKeysModal
          isOpen={true}
          onClose={mockOnClose}
          onKeysChanged={mockOnKeysChanged}
        />
      );

      const overlay = screen.getByText('Manage API Keys').closest('.modal-overlay');
      expect(overlay).toBeInTheDocument();
      fireEvent.click(overlay!);

      expect(mockOnClose).toHaveBeenCalledTimes(1);
    });

    it('should not close when modal content is clicked', () => {
      render(
        <ApiKeysModal
          isOpen={true}
          onClose={mockOnClose}
          onKeysChanged={mockOnKeysChanged}
        />
      );

      const modalContent = screen.getByText('Manage API Keys').closest('.modal-content');
      expect(modalContent).toBeInTheDocument();
      fireEvent.click(modalContent!);

      expect(mockOnClose).not.toHaveBeenCalled();
    });
  });

  describe('Saving API keys', () => {
    it('should save AssemblyAI key when Save button is clicked', async () => {
      render(
        <ApiKeysModal
          isOpen={true}
          onClose={mockOnClose}
          onKeysChanged={mockOnKeysChanged}
        />
      );

      const input = screen.getByPlaceholderText('Enter AssemblyAI API Key');
      const saveButtons = screen.getAllByText('Save');

      fireEvent.change(input, { target: { value: 'test-assembly-key' } });
      fireEvent.click(saveButtons[0]);

      await waitFor(() => {
        expect(mockSaveKey).toHaveBeenCalledWith('assemblyai_api_key', 'test-assembly-key');
      });

      expect(screen.getByText('AssemblyAI API Key saved successfully')).toBeInTheDocument();
    });

    it('should save Vapi key when Save button is clicked', async () => {
      render(
        <ApiKeysModal
          isOpen={true}
          onClose={mockOnClose}
          onKeysChanged={mockOnKeysChanged}
        />
      );

      const input = screen.getByPlaceholderText('Enter Vapi Public Key');
      const saveButtons = screen.getAllByText('Save');

      fireEvent.change(input, { target: { value: 'test-vapi-key' } });
      fireEvent.click(saveButtons[1]);

      await waitFor(() => {
        expect(mockSaveKey).toHaveBeenCalledWith('vapi_public_key', 'test-vapi-key');
      });

      expect(screen.getByText('Vapi Public Key saved successfully')).toBeInTheDocument();
    });

    it('should save LLM Proxy key when Save button is clicked', async () => {
      render(
        <ApiKeysModal
          isOpen={true}
          onClose={mockOnClose}
          onKeysChanged={mockOnKeysChanged}
        />
      );

      const input = screen.getByPlaceholderText('Enter LLM Proxy API Key');
      const saveButtons = screen.getAllByText('Save');

      fireEvent.change(input, { target: { value: 'test-llm-key' } });
      fireEvent.click(saveButtons[2]);

      await waitFor(() => {
        expect(mockSaveKey).toHaveBeenCalledWith('llm_proxy_api_key', 'test-llm-key');
      });

      expect(screen.getByText('LLM Proxy API Key saved successfully')).toBeInTheDocument();
    });

    it('should call onKeysChanged after successful save', async () => {
      render(
        <ApiKeysModal
          isOpen={true}
          onClose={mockOnClose}
          onKeysChanged={mockOnKeysChanged}
        />
      );

      const input = screen.getByPlaceholderText('Enter AssemblyAI API Key');
      const saveButtons = screen.getAllByText('Save');

      fireEvent.change(input, { target: { value: 'test-key' } });
      fireEvent.click(saveButtons[0]);

      await waitFor(() => {
        expect(mockOnKeysChanged).toHaveBeenCalledTimes(1);
      });
    });

    it('should emit api-keys-changed event after successful save', async () => {
      const eventListener = vi.fn();
      window.addEventListener('api-keys-changed', eventListener);

      render(
        <ApiKeysModal
          isOpen={true}
          onClose={mockOnClose}
          onKeysChanged={mockOnKeysChanged}
        />
      );

      const input = screen.getByPlaceholderText('Enter AssemblyAI API Key');
      const saveButtons = screen.getAllByText('Save');

      fireEvent.change(input, { target: { value: 'test-key' } });
      fireEvent.click(saveButtons[0]);

      await waitFor(() => {
        expect(eventListener).toHaveBeenCalledTimes(1);
      });

      window.removeEventListener('api-keys-changed', eventListener);
    });

    it('should disable Save button when input is empty', () => {
      render(
        <ApiKeysModal
          isOpen={true}
          onClose={mockOnClose}
          onKeysChanged={mockOnKeysChanged}
        />
      );

      const saveButtons = screen.getAllByText('Save');
      // All save buttons should be disabled when inputs are empty
      saveButtons.forEach((button) => {
        expect(button).toBeDisabled();
      });

      expect(mockSaveKey).not.toHaveBeenCalled();
    });

    it('should show error when save fails', async () => {
      mockSaveKey.mockRejectedValueOnce(new Error('Keychain error'));

      render(
        <ApiKeysModal
          isOpen={true}
          onClose={mockOnClose}
          onKeysChanged={mockOnKeysChanged}
        />
      );

      const input = screen.getByPlaceholderText('Enter AssemblyAI API Key');
      const saveButtons = screen.getAllByText('Save');

      fireEvent.change(input, { target: { value: 'test-key' } });
      fireEvent.click(saveButtons[0]);

      await waitFor(() => {
        expect(screen.getByText('Keychain error')).toBeInTheDocument();
      });
    });

    it('should disable Save button when loading', () => {
      vi.mocked(useApiKeysHook.useApiKeys).mockReturnValue({
        keys: {
          assemblyAi: null,
          vapiPublic: null,
          llmProxy: null,
        },
        status: {
          assemblyAi: false,
          vapiPublic: false,
          llmProxy: false,
        },
        loading: true,
        error: null,
        loadKeys: vi.fn().mockResolvedValue(undefined),
        saveKey: mockSaveKey,
        removeKey: mockRemoveKey,
        refreshStatus: vi.fn().mockResolvedValue(undefined),
      });

      render(
        <ApiKeysModal
          isOpen={true}
          onClose={mockOnClose}
          onKeysChanged={mockOnKeysChanged}
        />
      );

      const saveButtons = screen.getAllByText('Save');
      saveButtons.forEach((button) => {
        expect(button).toBeDisabled();
      });
    });

    it('should trim whitespace from key before saving', async () => {
      render(
        <ApiKeysModal
          isOpen={true}
          onClose={mockOnClose}
          onKeysChanged={mockOnKeysChanged}
        />
      );

      const input = screen.getByPlaceholderText('Enter AssemblyAI API Key');
      const saveButtons = screen.getAllByText('Save');

      fireEvent.change(input, { target: { value: '  test-key  ' } });
      fireEvent.click(saveButtons[0]);

      await waitFor(() => {
        expect(mockSaveKey).toHaveBeenCalledWith('assemblyai_api_key', 'test-key');
      });
    });
  });

  describe('Existing keys display', () => {
    beforeEach(() => {
      vi.mocked(useApiKeysHook.useApiKeys).mockReturnValue({
        keys: {
          assemblyAi: 'sk_1234567890abcdefghijklmnop',
          vapiPublic: 'vapi_public_key_xyz',
          llmProxy: 'llm_proxy_key_123',
        },
        status: {
          assemblyAi: true,
          vapiPublic: true,
          llmProxy: true,
        },
        loading: false,
        error: null,
        loadKeys: vi.fn().mockResolvedValue(undefined),
        saveKey: mockSaveKey,
        removeKey: mockRemoveKey,
        refreshStatus: vi.fn().mockResolvedValue(undefined),
      });
    });

    it('should mask existing keys by default', () => {
      render(
        <ApiKeysModal
          isOpen={true}
          onClose={mockOnClose}
          onKeysChanged={mockOnKeysChanged}
        />
      );

      // Keys should be masked: first 4 chars + bullets + last 4 chars
      // sk_1234567890abcdefghijklmnop (29 chars) -> sk_1 + 21 bullets + mnop
      expect(screen.getByText('sk_1•••••••••••••••••••••mnop')).toBeInTheDocument();
      // vapi_public_key_xyz (19 chars) -> vapi + 11 bullets + _xyz
      expect(screen.getByText('vapi•••••••••••_xyz')).toBeInTheDocument();
      // llm_proxy_key_123 (17 chars) -> llm_ + 9 bullets + _123
      expect(screen.getByText('llm_•••••••••_123')).toBeInTheDocument();
    });

    it('should reveal key when reveal button is clicked', () => {
      render(
        <ApiKeysModal
          isOpen={true}
          onClose={mockOnClose}
          onKeysChanged={mockOnKeysChanged}
        />
      );

      const revealButtons = screen.getAllByTitle('Reveal');
      fireEvent.click(revealButtons[0]);

      expect(screen.getByText('sk_1234567890abcdefghijklmnop')).toBeInTheDocument();
    });

    it('should hide key when hide button is clicked after revealing', () => {
      render(
        <ApiKeysModal
          isOpen={true}
          onClose={mockOnClose}
          onKeysChanged={mockOnKeysChanged}
        />
      );

      const revealButtons = screen.getAllByTitle('Reveal');
      fireEvent.click(revealButtons[0]);

      const hideButton = screen.getByTitle('Hide');
      fireEvent.click(hideButton);

      // sk_1234567890abcdefghijklmnop (29 chars) -> sk_1 + 21 bullets + mnop
      expect(screen.getByText('sk_1•••••••••••••••••••••mnop')).toBeInTheDocument();
    });

    it('should show Edit and Delete buttons for existing keys', () => {
      render(
        <ApiKeysModal
          isOpen={true}
          onClose={mockOnClose}
          onKeysChanged={mockOnKeysChanged}
        />
      );

      const editButtons = screen.getAllByText('Edit');
      const deleteButtons = screen.getAllByText('Delete');

      expect(editButtons).toHaveLength(3);
      expect(deleteButtons).toHaveLength(3);
    });
  });

  describe('Editing existing keys', () => {
    beforeEach(() => {
      vi.mocked(useApiKeysHook.useApiKeys).mockReturnValue({
        keys: {
          assemblyAi: 'sk_1234567890abcdefghijklmnop',
          vapiPublic: null,
          llmProxy: null,
        },
        status: {
          assemblyAi: true,
          vapiPublic: false,
          llmProxy: false,
        },
        loading: false,
        error: null,
        loadKeys: vi.fn().mockResolvedValue(undefined),
        saveKey: mockSaveKey,
        removeKey: mockRemoveKey,
        refreshStatus: vi.fn().mockResolvedValue(undefined),
      });
    });

    it('should switch to edit mode when Edit button is clicked', () => {
      render(
        <ApiKeysModal
          isOpen={true}
          onClose={mockOnClose}
          onKeysChanged={mockOnKeysChanged}
        />
      );

      const editButton = screen.getByText('Edit');
      fireEvent.click(editButton);

      expect(screen.getByPlaceholderText('Enter AssemblyAI API Key')).toBeInTheDocument();
      expect(screen.getByText('Cancel')).toBeInTheDocument();
    });

    it('should clear input when entering edit mode', () => {
      render(
        <ApiKeysModal
          isOpen={true}
          onClose={mockOnClose}
          onKeysChanged={mockOnKeysChanged}
        />
      );

      const editButton = screen.getByText('Edit');
      fireEvent.click(editButton);

      const input = screen.getByPlaceholderText(
        'Enter AssemblyAI API Key'
      ) as HTMLInputElement;
      expect(input.value).toBe('');
    });

    it('should cancel edit mode when Cancel button is clicked', () => {
      render(
        <ApiKeysModal
          isOpen={true}
          onClose={mockOnClose}
          onKeysChanged={mockOnKeysChanged}
        />
      );

      const editButton = screen.getByText('Edit');
      fireEvent.click(editButton);

      const cancelButton = screen.getByText('Cancel');
      fireEvent.click(cancelButton);

      expect(screen.queryByText('Cancel')).not.toBeInTheDocument();
      // sk_1234567890abcdefghijklmnop (29 chars) -> sk_1 + 21 bullets + mnop
      expect(screen.getByText('sk_1•••••••••••••••••••••mnop')).toBeInTheDocument();
    });

    it('should save updated key and exit edit mode', async () => {
      render(
        <ApiKeysModal
          isOpen={true}
          onClose={mockOnClose}
          onKeysChanged={mockOnKeysChanged}
        />
      );

      const editButton = screen.getByText('Edit');
      fireEvent.click(editButton);

      const input = screen.getByPlaceholderText('Enter AssemblyAI API Key');
      fireEvent.change(input, { target: { value: 'new-key-value' } });

      const saveButtons = screen.getAllByText('Save');
      fireEvent.click(saveButtons[0]);

      await waitFor(() => {
        expect(mockSaveKey).toHaveBeenCalledWith('assemblyai_api_key', 'new-key-value');
      });

      await waitFor(() => {
        expect(screen.queryByText('Cancel')).not.toBeInTheDocument();
      });
    });
  });

  describe('Deleting API keys', () => {
    beforeEach(() => {
      vi.mocked(useApiKeysHook.useApiKeys).mockReturnValue({
        keys: {
          assemblyAi: 'sk_1234567890abcdefghijklmnop',
          vapiPublic: null,
          llmProxy: null,
        },
        status: {
          assemblyAi: true,
          vapiPublic: false,
          llmProxy: false,
        },
        loading: false,
        error: null,
        loadKeys: vi.fn().mockResolvedValue(undefined),
        saveKey: mockSaveKey,
        removeKey: mockRemoveKey,
        refreshStatus: vi.fn().mockResolvedValue(undefined),
      });
    });

    it('should show confirmation dialog when Delete is clicked', () => {
      const confirmSpy = vi.spyOn(window, 'confirm').mockReturnValue(false);

      render(
        <ApiKeysModal
          isOpen={true}
          onClose={mockOnClose}
          onKeysChanged={mockOnKeysChanged}
        />
      );

      const deleteButton = screen.getByText('Delete');
      fireEvent.click(deleteButton);

      expect(confirmSpy).toHaveBeenCalledWith(
        'Are you sure you want to delete the AssemblyAI API Key?'
      );

      confirmSpy.mockRestore();
    });

    it('should delete key when confirmed', async () => {
      const confirmSpy = vi.spyOn(window, 'confirm').mockReturnValue(true);

      render(
        <ApiKeysModal
          isOpen={true}
          onClose={mockOnClose}
          onKeysChanged={mockOnKeysChanged}
        />
      );

      const deleteButton = screen.getByText('Delete');
      fireEvent.click(deleteButton);

      await waitFor(() => {
        expect(mockRemoveKey).toHaveBeenCalledWith('assemblyai_api_key');
      });

      expect(screen.getByText('AssemblyAI API Key deleted successfully')).toBeInTheDocument();

      confirmSpy.mockRestore();
    });

    it('should not delete key when cancelled', async () => {
      const confirmSpy = vi.spyOn(window, 'confirm').mockReturnValue(false);

      render(
        <ApiKeysModal
          isOpen={true}
          onClose={mockOnClose}
          onKeysChanged={mockOnKeysChanged}
        />
      );

      const deleteButton = screen.getByText('Delete');
      fireEvent.click(deleteButton);

      expect(mockRemoveKey).not.toHaveBeenCalled();

      confirmSpy.mockRestore();
    });

    it('should call onKeysChanged after successful delete', async () => {
      const confirmSpy = vi.spyOn(window, 'confirm').mockReturnValue(true);

      render(
        <ApiKeysModal
          isOpen={true}
          onClose={mockOnClose}
          onKeysChanged={mockOnKeysChanged}
        />
      );

      const deleteButton = screen.getByText('Delete');
      fireEvent.click(deleteButton);

      await waitFor(() => {
        expect(mockOnKeysChanged).toHaveBeenCalledTimes(1);
      });

      confirmSpy.mockRestore();
    });

    it('should emit api-keys-changed event after successful delete', async () => {
      const confirmSpy = vi.spyOn(window, 'confirm').mockReturnValue(true);
      const eventListener = vi.fn();
      window.addEventListener('api-keys-changed', eventListener);

      render(
        <ApiKeysModal
          isOpen={true}
          onClose={mockOnClose}
          onKeysChanged={mockOnKeysChanged}
        />
      );

      const deleteButton = screen.getByText('Delete');
      fireEvent.click(deleteButton);

      await waitFor(() => {
        expect(eventListener).toHaveBeenCalledTimes(1);
      });

      window.removeEventListener('api-keys-changed', eventListener);
      confirmSpy.mockRestore();
    });

    it('should show error when delete fails', async () => {
      const confirmSpy = vi.spyOn(window, 'confirm').mockReturnValue(true);
      mockRemoveKey.mockRejectedValueOnce(new Error('Keychain error'));

      render(
        <ApiKeysModal
          isOpen={true}
          onClose={mockOnClose}
          onKeysChanged={mockOnKeysChanged}
        />
      );

      const deleteButton = screen.getByText('Delete');
      fireEvent.click(deleteButton);

      await waitFor(() => {
        expect(screen.getByText('Keychain error')).toBeInTheDocument();
      });

      confirmSpy.mockRestore();
    });
  });

  describe('Error handling', () => {
    it('should display error from useApiKeys hook', () => {
      vi.mocked(useApiKeysHook.useApiKeys).mockReturnValue({
        keys: {
          assemblyAi: null,
          vapiPublic: null,
          llmProxy: null,
        },
        status: {
          assemblyAi: false,
          vapiPublic: false,
          llmProxy: false,
        },
        loading: false,
        error: 'Failed to load keys from keychain',
        loadKeys: vi.fn().mockResolvedValue(undefined),
        saveKey: mockSaveKey,
        removeKey: mockRemoveKey,
        refreshStatus: vi.fn().mockResolvedValue(undefined),
      });

      render(
        <ApiKeysModal
          isOpen={true}
          onClose={mockOnClose}
          onKeysChanged={mockOnKeysChanged}
        />
      );

      expect(screen.getByText('Failed to load keys from keychain')).toBeInTheDocument();
    });

    it('should clear error when input changes', async () => {
      // Setup mock to reject on first call
      mockSaveKey.mockRejectedValueOnce(new Error('Network error'));

      render(
        <ApiKeysModal
          isOpen={true}
          onClose={mockOnClose}
          onKeysChanged={mockOnKeysChanged}
        />
      );

      const input = screen.getByPlaceholderText('Enter AssemblyAI API Key');
      const saveButtons = screen.getAllByText('Save');

      // Trigger error by providing a value and attempting to save (which will fail)
      fireEvent.change(input, { target: { value: 'test-key' } });
      fireEvent.click(saveButtons[0]);

      await waitFor(() => {
        expect(screen.getByText('Network error')).toBeInTheDocument();
      });

      // Change input - error should clear
      fireEvent.change(input, { target: { value: 'test-key-2' } });

      expect(screen.queryByText('Network error')).not.toBeInTheDocument();
    });

    it('should clear success message when input changes', async () => {
      render(
        <ApiKeysModal
          isOpen={true}
          onClose={mockOnClose}
          onKeysChanged={mockOnKeysChanged}
        />
      );

      const input = screen.getByPlaceholderText('Enter AssemblyAI API Key');
      const saveButtons = screen.getAllByText('Save');

      // Trigger success
      fireEvent.change(input, { target: { value: 'test-key' } });
      fireEvent.click(saveButtons[0]);

      await waitFor(() => {
        expect(screen.getByText('AssemblyAI API Key saved successfully')).toBeInTheDocument();
      });

      // Change input - success should clear
      fireEvent.change(input, { target: { value: 'new-value' } });

      expect(
        screen.queryByText('AssemblyAI API Key saved successfully')
      ).not.toBeInTheDocument();
    });
  });
});
