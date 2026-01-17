import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { VoicePlaybackControls } from '../VoicePlaybackControls';
import type { VapiTtsState, VapiTtsActions } from '../../hooks/useVapiTts';

describe('VoicePlaybackControls', () => {
  let mockState: VapiTtsState;
  let mockActions: VapiTtsActions;

  beforeEach(() => {
    vi.clearAllMocks();

    mockActions = {
      speak: vi.fn(),
      pause: vi.fn(),
      resume: vi.fn(),
      stop: vi.fn(),
      mute: vi.fn(),
      unmute: vi.fn(),
    };
  });

  describe('visibility', () => {
    it('should not render when nothing is playing', () => {
      mockState = {
        isPlaying: false,
        isPaused: false,
        isMuted: false,
        error: null,
        currentText: null,
      };

      const { container } = render(
        <VoicePlaybackControls state={mockState} actions={mockActions} />
      );

      expect(container.firstChild).toBeNull();
    });

    it('should render when playing', () => {
      mockState = {
        isPlaying: true,
        isPaused: false,
        isMuted: false,
        error: null,
        currentText: 'Hello world',
      };

      render(<VoicePlaybackControls state={mockState} actions={mockActions} />);

      expect(screen.getByText('Speaking')).toBeInTheDocument();
    });

    it('should render when paused', () => {
      mockState = {
        isPlaying: false,
        isPaused: true,
        isMuted: false,
        error: null,
        currentText: 'Hello world',
      };

      render(<VoicePlaybackControls state={mockState} actions={mockActions} />);

      expect(screen.getByText('Paused')).toBeInTheDocument();
    });
  });

  describe('current text display', () => {
    it('should display current text when available', () => {
      mockState = {
        isPlaying: true,
        isPaused: false,
        isMuted: false,
        error: null,
        currentText: 'Hello world',
      };

      render(<VoicePlaybackControls state={mockState} actions={mockActions} />);

      expect(screen.getByText('Hello world...')).toBeInTheDocument();
    });

    it('should truncate long text to 50 characters', () => {
      mockState = {
        isPlaying: true,
        isPaused: false,
        isMuted: false,
        error: null,
        currentText: 'This is a very long text that should be truncated because it exceeds fifty characters',
      };

      const { container } = render(<VoicePlaybackControls state={mockState} actions={mockActions} />);

      // Component truncates at 50 chars and adds "..."
      // Text content might be split across nodes, so use textContent
      const playbackText = container.querySelector('.playback-text');
      expect(playbackText?.textContent).toBe('This is a very long text that should be truncated ...');
    });

    it('should not display text when null', () => {
      mockState = {
        isPlaying: true,
        isPaused: false,
        isMuted: false,
        error: null,
        currentText: null,
      };

      const { container } = render(<VoicePlaybackControls state={mockState} actions={mockActions} />);

      expect(container.querySelector('.playback-text')).not.toBeInTheDocument();
    });
  });

  describe('pause/resume button', () => {
    it('should show pause button when playing', () => {
      mockState = {
        isPlaying: true,
        isPaused: false,
        isMuted: false,
        error: null,
        currentText: 'Hello world',
      };

      render(<VoicePlaybackControls state={mockState} actions={mockActions} />);

      const pauseButton = screen.getByTitle('Pause');
      expect(pauseButton).toBeInTheDocument();
      expect(pauseButton.textContent).toBe('⏸️');
    });

    it('should show resume button when paused', () => {
      mockState = {
        isPlaying: false,
        isPaused: true,
        isMuted: false,
        error: null,
        currentText: 'Hello world',
      };

      render(<VoicePlaybackControls state={mockState} actions={mockActions} />);

      const resumeButton = screen.getByTitle('Resume');
      expect(resumeButton).toBeInTheDocument();
      expect(resumeButton.textContent).toBe('▶️');
    });

    it('should call pause when pause button is clicked', () => {
      mockState = {
        isPlaying: true,
        isPaused: false,
        isMuted: false,
        error: null,
        currentText: 'Hello world',
      };

      render(<VoicePlaybackControls state={mockState} actions={mockActions} />);

      const pauseButton = screen.getByTitle('Pause');
      fireEvent.click(pauseButton);

      expect(mockActions.pause).toHaveBeenCalledTimes(1);
    });

    it('should call resume when resume button is clicked', () => {
      mockState = {
        isPlaying: false,
        isPaused: true,
        isMuted: false,
        error: null,
        currentText: 'Hello world',
      };

      render(<VoicePlaybackControls state={mockState} actions={mockActions} />);

      const resumeButton = screen.getByTitle('Resume');
      fireEvent.click(resumeButton);

      expect(mockActions.resume).toHaveBeenCalledTimes(1);
    });
  });

  describe('stop button', () => {
    it('should call stop when stop button is clicked', () => {
      mockState = {
        isPlaying: true,
        isPaused: false,
        isMuted: false,
        error: null,
        currentText: 'Hello world',
      };

      render(<VoicePlaybackControls state={mockState} actions={mockActions} />);

      const stopButton = screen.getByTitle('Stop');
      fireEvent.click(stopButton);

      expect(mockActions.stop).toHaveBeenCalledTimes(1);
    });
  });

  describe('mute/unmute button', () => {
    it('should show unmuted icon when not muted', () => {
      mockState = {
        isPlaying: true,
        isPaused: false,
        isMuted: false,
        error: null,
        currentText: 'Hello world',
      };

      render(<VoicePlaybackControls state={mockState} actions={mockActions} />);

      const muteButton = screen.getByTitle('Mute');
      expect(muteButton).toBeInTheDocument();
      expect(muteButton.textContent).toBe('🔊');
      expect(muteButton).not.toHaveClass('active');
    });

    it('should show muted icon when muted', () => {
      mockState = {
        isPlaying: true,
        isPaused: false,
        isMuted: true,
        error: null,
        currentText: 'Hello world',
      };

      render(<VoicePlaybackControls state={mockState} actions={mockActions} />);

      const unmuteButton = screen.getByTitle('Unmute');
      expect(unmuteButton).toBeInTheDocument();
      expect(unmuteButton.textContent).toBe('🔇');
      expect(unmuteButton).toHaveClass('active');
    });

    it('should call mute when mute button is clicked', () => {
      mockState = {
        isPlaying: true,
        isPaused: false,
        isMuted: false,
        error: null,
        currentText: 'Hello world',
      };

      render(<VoicePlaybackControls state={mockState} actions={mockActions} />);

      const muteButton = screen.getByTitle('Mute');
      fireEvent.click(muteButton);

      expect(mockActions.mute).toHaveBeenCalledTimes(1);
    });

    it('should call unmute when unmute button is clicked', () => {
      mockState = {
        isPlaying: true,
        isPaused: false,
        isMuted: true,
        error: null,
        currentText: 'Hello world',
      };

      render(<VoicePlaybackControls state={mockState} actions={mockActions} />);

      const unmuteButton = screen.getByTitle('Unmute');
      fireEvent.click(unmuteButton);

      expect(mockActions.unmute).toHaveBeenCalledTimes(1);
    });
  });

  describe('error display', () => {
    it('should display error when present', () => {
      mockState = {
        isPlaying: true,
        isPaused: false,
        isMuted: false,
        error: 'Playback failed',
        currentText: 'Hello world',
      };

      render(<VoicePlaybackControls state={mockState} actions={mockActions} />);

      expect(screen.getByText('Playback failed')).toBeInTheDocument();
      expect(screen.getByText('⚠️')).toBeInTheDocument();
    });

    it('should not display error section when no error', () => {
      mockState = {
        isPlaying: true,
        isPaused: false,
        isMuted: false,
        error: null,
        currentText: 'Hello world',
      };

      const { container } = render(
        <VoicePlaybackControls state={mockState} actions={mockActions} />
      );

      expect(container.querySelector('.playback-error')).not.toBeInTheDocument();
    });
  });

  describe('styling', () => {
    it('should apply custom className', () => {
      mockState = {
        isPlaying: true,
        isPaused: false,
        isMuted: false,
        error: null,
        currentText: 'Hello world',
      };

      const { container } = render(
        <VoicePlaybackControls
          state={mockState}
          actions={mockActions}
          className="custom-class"
        />
      );

      const controls = container.querySelector('.voice-playback-controls');
      expect(controls).toHaveClass('custom-class');
    });
  });
});
