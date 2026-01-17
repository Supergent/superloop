import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { VoiceInput, type VoiceInputRef } from '../VoiceInput';
import * as useAssemblyAIStreamingHook from '../../hooks/useAssemblyAIStreaming';
import React from 'react';

// Mock the useAssemblyAIStreaming hook
vi.mock('../../hooks/useAssemblyAIStreaming', () => ({
  useAssemblyAIStreaming: vi.fn(),
}));

describe('VoiceInput', () => {
  let mockStart: ReturnType<typeof vi.fn>;
  let mockStop: ReturnType<typeof vi.fn>;
  let mockOnVoiceStart: ReturnType<typeof vi.fn>;
  let mockOnVoiceEnd: ReturnType<typeof vi.fn>;
  let mockOnInterimTranscript: ReturnType<typeof vi.fn>;
  let mockOnFinalTranscript: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    vi.clearAllMocks();

    mockStart = vi.fn().mockResolvedValue(undefined);
    mockStop = vi.fn();
    mockOnVoiceStart = vi.fn();
    mockOnVoiceEnd = vi.fn();
    mockOnInterimTranscript = vi.fn();
    mockOnFinalTranscript = vi.fn();

    // Setup default mock for useAssemblyAIStreaming
    vi.mocked(useAssemblyAIStreamingHook.useAssemblyAIStreaming).mockReturnValue([
      {
        isRecording: false,
        interimTranscript: '',
        finalTranscript: '',
        error: null,
      },
      {
        start: mockStart,
        stop: mockStop,
      },
    ]);
  });

  describe('Rendering', () => {
    it('should render voice button', () => {
      render(<VoiceInput apiKey="test-key" />);

      expect(screen.getByRole('button')).toBeInTheDocument();
      expect(screen.getByText('🎤')).toBeInTheDocument();
      expect(screen.getByText('Voice Input')).toBeInTheDocument();
    });

    it('should be disabled when no API key is provided', () => {
      render(<VoiceInput apiKey="" />);

      const button = screen.getByRole('button');
      expect(button).toBeDisabled();
      expect(screen.getByText('Voice (Configure API Key)')).toBeInTheDocument();
    });

    it('should be disabled when disabled prop is true', () => {
      render(<VoiceInput apiKey="test-key" disabled={true} />);

      const button = screen.getByRole('button');
      expect(button).toBeDisabled();
    });

    it('should show correct title when API key is configured', () => {
      render(<VoiceInput apiKey="test-key" />);

      const button = screen.getByRole('button');
      expect(button).toHaveAttribute('title', 'Click to start voice input');
    });

    it('should show correct title when API key is not configured', () => {
      render(<VoiceInput apiKey="" />);

      const button = screen.getByRole('button');
      expect(button).toHaveAttribute('title', 'Configure API key to enable voice input');
    });

    it('should add listening class when recording', () => {
      vi.mocked(useAssemblyAIStreamingHook.useAssemblyAIStreaming).mockReturnValue([
        {
          isRecording: true,
          interimTranscript: '',
          finalTranscript: '',
          error: null,
        },
        {
          start: mockStart,
          stop: mockStop,
        },
      ]);

      render(<VoiceInput apiKey="test-key" />);

      const button = screen.getByRole('button');
      expect(button).toHaveClass('listening');
      expect(screen.getByText('Listening...')).toBeInTheDocument();
    });
  });

  describe('Voice control via button clicks', () => {
    it('should start recording when button is clicked', async () => {
      render(
        <VoiceInput
          apiKey="test-key"
          onVoiceStart={mockOnVoiceStart}
          onVoiceEnd={mockOnVoiceEnd}
        />
      );

      const button = screen.getByRole('button');
      fireEvent.click(button);

      await waitFor(() => {
        expect(mockStart).toHaveBeenCalledTimes(1);
      });

      await waitFor(() => {
        expect(mockOnVoiceStart).toHaveBeenCalledTimes(1);
      });
    });

    it('should stop recording when button is clicked while recording', async () => {
      vi.mocked(useAssemblyAIStreamingHook.useAssemblyAIStreaming).mockReturnValue([
        {
          isRecording: true,
          interimTranscript: '',
          finalTranscript: '',
          error: null,
        },
        {
          start: mockStart,
          stop: mockStop,
        },
      ]);

      render(
        <VoiceInput
          apiKey="test-key"
          onVoiceStart={mockOnVoiceStart}
          onVoiceEnd={mockOnVoiceEnd}
        />
      );

      const button = screen.getByRole('button');
      fireEvent.click(button);

      await waitFor(() => {
        expect(mockStop).toHaveBeenCalledTimes(1);
      });

      await waitFor(() => {
        expect(mockOnVoiceEnd).toHaveBeenCalledTimes(1);
      });
    });

    it('should toggle between start and stop', async () => {
      const { rerender } = render(
        <VoiceInput
          apiKey="test-key"
          onVoiceStart={mockOnVoiceStart}
          onVoiceEnd={mockOnVoiceEnd}
        />
      );

      const button = screen.getByRole('button');

      // First click - start
      fireEvent.click(button);

      await waitFor(() => {
        expect(mockStart).toHaveBeenCalledTimes(1);
      });

      // Update state to recording
      vi.mocked(useAssemblyAIStreamingHook.useAssemblyAIStreaming).mockReturnValue([
        {
          isRecording: true,
          interimTranscript: '',
          finalTranscript: '',
          error: null,
        },
        {
          start: mockStart,
          stop: mockStop,
        },
      ]);

      rerender(
        <VoiceInput
          apiKey="test-key"
          onVoiceStart={mockOnVoiceStart}
          onVoiceEnd={mockOnVoiceEnd}
        />
      );

      // Second click - stop
      fireEvent.click(button);

      await waitFor(() => {
        expect(mockStop).toHaveBeenCalledTimes(1);
      });
    });
  });

  describe('Programmatic control via ref', () => {
    it('should expose start method via ref', async () => {
      const ref = React.createRef<VoiceInputRef>();

      render(<VoiceInput ref={ref} apiKey="test-key" onVoiceStart={mockOnVoiceStart} />);

      await ref.current?.start();

      expect(mockStart).toHaveBeenCalledTimes(1);
      expect(mockOnVoiceStart).toHaveBeenCalledTimes(1);
    });

    it('should expose stop method via ref', async () => {
      vi.mocked(useAssemblyAIStreamingHook.useAssemblyAIStreaming).mockReturnValue([
        {
          isRecording: true,
          interimTranscript: '',
          finalTranscript: '',
          error: null,
        },
        {
          start: mockStart,
          stop: mockStop,
        },
      ]);

      const ref = React.createRef<VoiceInputRef>();

      render(<VoiceInput ref={ref} apiKey="test-key" onVoiceEnd={mockOnVoiceEnd} />);

      ref.current?.stop();

      expect(mockStop).toHaveBeenCalledTimes(1);
      expect(mockOnVoiceEnd).toHaveBeenCalledTimes(1);
    });

    it('should expose toggle method via ref', async () => {
      const ref = React.createRef<VoiceInputRef>();

      render(<VoiceInput ref={ref} apiKey="test-key" />);

      await ref.current?.toggle();

      expect(mockStart).toHaveBeenCalledTimes(1);
    });

    it('should expose isRecording property via ref', () => {
      vi.mocked(useAssemblyAIStreamingHook.useAssemblyAIStreaming).mockReturnValue([
        {
          isRecording: true,
          interimTranscript: '',
          finalTranscript: '',
          error: null,
        },
        {
          start: mockStart,
          stop: mockStop,
        },
      ]);

      const ref = React.createRef<VoiceInputRef>();

      render(<VoiceInput ref={ref} apiKey="test-key" />);

      expect(ref.current?.isRecording).toBe(true);
    });

    it('should not start if already recording', async () => {
      vi.mocked(useAssemblyAIStreamingHook.useAssemblyAIStreaming).mockReturnValue([
        {
          isRecording: true,
          interimTranscript: '',
          finalTranscript: '',
          error: null,
        },
        {
          start: mockStart,
          stop: mockStop,
        },
      ]);

      const ref = React.createRef<VoiceInputRef>();

      render(<VoiceInput ref={ref} apiKey="test-key" onVoiceStart={mockOnVoiceStart} />);

      await ref.current?.start();

      expect(mockStart).not.toHaveBeenCalled();
      expect(mockOnVoiceStart).not.toHaveBeenCalled();
    });

    it('should not stop if not recording', () => {
      const ref = React.createRef<VoiceInputRef>();

      render(<VoiceInput ref={ref} apiKey="test-key" onVoiceEnd={mockOnVoiceEnd} />);

      ref.current?.stop();

      expect(mockStop).not.toHaveBeenCalled();
      expect(mockOnVoiceEnd).not.toHaveBeenCalled();
    });

    it('should allow stopping active recording even when disabled', () => {
      vi.mocked(useAssemblyAIStreamingHook.useAssemblyAIStreaming).mockReturnValue([
        {
          isRecording: true,
          interimTranscript: '',
          finalTranscript: '',
          error: null,
        },
        {
          start: mockStart,
          stop: mockStop,
        },
      ]);

      const ref = React.createRef<VoiceInputRef>();

      render(<VoiceInput ref={ref} apiKey="test-key" disabled={true} onVoiceEnd={mockOnVoiceEnd} />);

      ref.current?.stop();

      expect(mockStop).toHaveBeenCalledTimes(1);
      expect(mockOnVoiceEnd).toHaveBeenCalledTimes(1);
    });
  });

  describe('Controlled mode via isActive prop', () => {
    it('should start recording when isActive becomes true', async () => {
      const { rerender } = render(<VoiceInput apiKey="test-key" isActive={false} />);

      expect(mockStart).not.toHaveBeenCalled();

      rerender(<VoiceInput apiKey="test-key" isActive={true} />);

      await waitFor(() => {
        expect(mockStart).toHaveBeenCalledTimes(1);
      });
    });

    it('should stop recording when isActive becomes false', async () => {
      vi.mocked(useAssemblyAIStreamingHook.useAssemblyAIStreaming).mockReturnValue([
        {
          isRecording: true,
          interimTranscript: '',
          finalTranscript: '',
          error: null,
        },
        {
          start: mockStart,
          stop: mockStop,
        },
      ]);

      const { rerender } = render(<VoiceInput apiKey="test-key" isActive={true} />);

      rerender(<VoiceInput apiKey="test-key" isActive={false} />);

      await waitFor(() => {
        expect(mockStop).toHaveBeenCalled();
      });
    });

    it('should not start if already recording when isActive becomes true', async () => {
      vi.mocked(useAssemblyAIStreamingHook.useAssemblyAIStreaming).mockReturnValue([
        {
          isRecording: true,
          interimTranscript: '',
          finalTranscript: '',
          error: null,
        },
        {
          start: mockStart,
          stop: mockStop,
        },
      ]);

      const { rerender } = render(<VoiceInput apiKey="test-key" isActive={false} />);

      rerender(<VoiceInput apiKey="test-key" isActive={true} />);

      // Since we're already recording, start should not be called
      expect(mockStart).not.toHaveBeenCalled();
    });
  });

  describe('Transcript handling', () => {
    it('should display interim transcript', () => {
      vi.mocked(useAssemblyAIStreamingHook.useAssemblyAIStreaming).mockReturnValue([
        {
          isRecording: true,
          interimTranscript: 'Hello world',
          finalTranscript: '',
          error: null,
        },
        {
          start: mockStart,
          stop: mockStop,
        },
      ]);

      render(<VoiceInput apiKey="test-key" />);

      expect(screen.getByText('Hearing:')).toBeInTheDocument();
      expect(screen.getByText('Hello world')).toBeInTheDocument();
    });

    it('should not display interim transcript when empty', () => {
      render(<VoiceInput apiKey="test-key" />);

      expect(screen.queryByText('Hearing:')).not.toBeInTheDocument();
    });

    it('should call onInterimTranscript callback', () => {
      let capturedCallback: ((event: any) => void) | null = null;

      vi.mocked(useAssemblyAIStreamingHook.useAssemblyAIStreaming).mockImplementation(
        (config, interimCallback) => {
          capturedCallback = interimCallback;
          return [
            {
              isRecording: false,
              interimTranscript: '',
              finalTranscript: '',
              error: null,
            },
            {
              start: mockStart,
              stop: mockStop,
            },
          ];
        }
      );

      render(
        <VoiceInput apiKey="test-key" onInterimTranscript={mockOnInterimTranscript} />
      );

      // Simulate interim transcript event
      capturedCallback?.({ text: 'test transcript', isFinal: false });

      expect(mockOnInterimTranscript).toHaveBeenCalledWith('test transcript');
    });

    it('should call onFinalTranscript callback', () => {
      let capturedCallback: ((event: any) => void) | null = null;

      vi.mocked(useAssemblyAIStreamingHook.useAssemblyAIStreaming).mockImplementation(
        (config, interimCallback, finalCallback) => {
          capturedCallback = finalCallback;
          return [
            {
              isRecording: false,
              interimTranscript: '',
              finalTranscript: '',
              error: null,
            },
            {
              start: mockStart,
              stop: mockStop,
            },
          ];
        }
      );

      render(
        <VoiceInput apiKey="test-key" onFinalTranscript={mockOnFinalTranscript} />
      );

      // Simulate final transcript event
      capturedCallback?.({ text: 'final transcript', isFinal: true });

      expect(mockOnFinalTranscript).toHaveBeenCalledWith('final transcript');
    });
  });

  describe('Error handling', () => {
    it('should display error message', () => {
      vi.mocked(useAssemblyAIStreamingHook.useAssemblyAIStreaming).mockReturnValue([
        {
          isRecording: false,
          interimTranscript: '',
          finalTranscript: '',
          error: 'Microphone permission denied',
        },
        {
          start: mockStart,
          stop: mockStop,
        },
      ]);

      render(<VoiceInput apiKey="test-key" />);

      expect(screen.getByText('⚠️')).toBeInTheDocument();
      expect(screen.getByText('Microphone permission denied')).toBeInTheDocument();
    });

    it('should not display error when null', () => {
      render(<VoiceInput apiKey="test-key" />);

      expect(screen.queryByText('⚠️')).not.toBeInTheDocument();
    });

    it('should log errors to console', () => {
      const consoleErrorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
      let capturedErrorCallback: ((error: Error) => void) | null = null;

      vi.mocked(useAssemblyAIStreamingHook.useAssemblyAIStreaming).mockImplementation(
        (config, interimCallback, finalCallback, errorCallback) => {
          capturedErrorCallback = errorCallback;
          return [
            {
              isRecording: false,
              interimTranscript: '',
              finalTranscript: '',
              error: null,
            },
            {
              start: mockStart,
              stop: mockStop,
            },
          ];
        }
      );

      render(<VoiceInput apiKey="test-key" />);

      const testError = new Error('Test error');
      capturedErrorCallback?.(testError);

      expect(consoleErrorSpy).toHaveBeenCalledWith('Voice input error:', testError);

      consoleErrorSpy.mockRestore();
    });
  });

  describe('API key configuration', () => {
    it('should pass API key to useAssemblyAIStreaming', () => {
      render(<VoiceInput apiKey="test-assembly-key" />);

      expect(useAssemblyAIStreamingHook.useAssemblyAIStreaming).toHaveBeenCalledWith(
        { apiKey: 'test-assembly-key' },
        expect.any(Function),
        expect.any(Function),
        expect.any(Function)
      );
    });

    it('should update API key when prop changes', () => {
      const { rerender } = render(<VoiceInput apiKey="key1" />);

      expect(useAssemblyAIStreamingHook.useAssemblyAIStreaming).toHaveBeenCalledWith(
        { apiKey: 'key1' },
        expect.any(Function),
        expect.any(Function),
        expect.any(Function)
      );

      rerender(<VoiceInput apiKey="key2" />);

      expect(useAssemblyAIStreamingHook.useAssemblyAIStreaming).toHaveBeenCalledWith(
        { apiKey: 'key2' },
        expect.any(Function),
        expect.any(Function),
        expect.any(Function)
      );
    });
  });
});
