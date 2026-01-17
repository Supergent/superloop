import React from 'react';
import type { VapiTtsState, VapiTtsActions } from '../hooks/useVapiTts';

export interface VoicePlaybackControlsProps {
  /** Current TTS state */
  state: VapiTtsState;
  /** TTS control actions */
  actions: VapiTtsActions;
  /** Optional className for styling */
  className?: string;
}

/**
 * Voice playback controls component
 * Exposes pause/resume/mute controls for TTS playback
 */
export function VoicePlaybackControls({
  state,
  actions,
  className = '',
}: VoicePlaybackControlsProps) {
  // Don't render if nothing is playing
  if (!state.isPlaying && !state.isPaused) {
    return null;
  }

  const handlePauseResume = () => {
    if (state.isPaused) {
      actions.resume();
    } else {
      actions.pause();
    }
  };

  const handleMuteToggle = () => {
    if (state.isMuted) {
      actions.unmute();
    } else {
      actions.mute();
    }
  };

  return (
    <div className={`voice-playback-controls ${className}`}>
      <div className="playback-header">
        <span className="playback-label">
          {state.isPaused ? 'Paused' : 'Speaking'}
        </span>
        {state.currentText && (
          <span className="playback-text">{state.currentText.substring(0, 50)}...</span>
        )}
      </div>

      <div className="playback-actions">
        <button
          className="playback-button"
          onClick={handlePauseResume}
          title={state.isPaused ? 'Resume' : 'Pause'}
        >
          {state.isPaused ? '▶️' : '⏸️'}
        </button>

        <button
          className="playback-button"
          onClick={actions.stop}
          title="Stop"
        >
          ⏹️
        </button>

        <button
          className={`playback-button ${state.isMuted ? 'active' : ''}`}
          onClick={handleMuteToggle}
          title={state.isMuted ? 'Unmute' : 'Mute'}
        >
          {state.isMuted ? '🔇' : '🔊'}
        </button>
      </div>

      {state.error && (
        <div className="playback-error">
          <span className="error-icon">⚠️</span>
          <span className="error-text">{state.error}</span>
        </div>
      )}
    </div>
  );
}
