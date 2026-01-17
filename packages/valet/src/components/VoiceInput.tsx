import React, { useCallback, useImperativeHandle, forwardRef } from 'react';
import { useAssemblyAIStreaming, TranscriptEvent } from '../hooks/useAssemblyAIStreaming';

export interface VoiceInputProps {
  /** Callback when voice input starts */
  onVoiceStart?: () => void;
  /** Callback when voice input ends */
  onVoiceEnd?: () => void;
  /** Callback for interim transcripts (real-time updates) */
  onInterimTranscript?: (text: string) => void;
  /** Callback for final transcripts (complete utterances) */
  onFinalTranscript?: (text: string) => void;
  /** AssemblyAI API key */
  apiKey?: string;
  /** Whether the component is disabled */
  disabled?: boolean;
  /** Whether voice input is active (for controlled mode) */
  isActive?: boolean;
}

export interface VoiceInputRef {
  /** Programmatically start voice recording */
  start: () => Promise<void>;
  /** Programmatically stop voice recording */
  stop: () => void;
  /** Toggle voice recording */
  toggle: () => Promise<void>;
  /** Whether currently recording */
  isRecording: boolean;
}

/**
 * Voice input component with AssemblyAI streaming integration.
 * Captures speech and provides real-time transcription.
 *
 * Can be controlled via ref for programmatic start/stop/toggle.
 */
export const VoiceInput = forwardRef<VoiceInputRef, VoiceInputProps>(({
  onVoiceStart,
  onVoiceEnd,
  onInterimTranscript,
  onFinalTranscript,
  apiKey = '',
  disabled = false,
  isActive: isActiveProp,
}, ref) => {
  const handleInterimTranscript = useCallback((event: TranscriptEvent) => {
    onInterimTranscript?.(event.text);
  }, [onInterimTranscript]);

  const handleFinalTranscript = useCallback((event: TranscriptEvent) => {
    onFinalTranscript?.(event.text);
  }, [onFinalTranscript]);

  const handleError = useCallback((error: Error) => {
    console.error('Voice input error:', error);
  }, []);

  const [state, actions] = useAssemblyAIStreaming(
    { apiKey },
    handleInterimTranscript,
    handleFinalTranscript,
    handleError
  );

  const handleStart = useCallback(async () => {
    if (!state.isRecording) {
      await actions.start();
      onVoiceStart?.();
    }
  }, [state.isRecording, actions, onVoiceStart]);

  const handleStop = useCallback(() => {
    if (state.isRecording) {
      actions.stop();
      onVoiceEnd?.();
    }
  }, [state.isRecording, actions, onVoiceEnd]);

  const handleToggle = useCallback(async () => {
    if (state.isRecording) {
      handleStop();
    } else {
      await handleStart();
    }
  }, [state.isRecording, handleStart, handleStop]);

  // Expose programmatic controls via ref
  useImperativeHandle(ref, () => ({
    start: handleStart,
    stop: handleStop,
    toggle: handleToggle,
    isRecording: state.isRecording,
  }), [handleStart, handleStop, handleToggle, state.isRecording]);

  // Support controlled mode via isActive prop
  React.useEffect(() => {
    if (isActiveProp !== undefined) {
      if (isActiveProp && !state.isRecording) {
        handleStart();
      } else if (!isActiveProp && state.isRecording) {
        handleStop();
      }
    }
  }, [isActiveProp, state.isRecording, handleStart, handleStop]);

  const isActive = apiKey && apiKey.length > 0;

  return (
    <div className="voice-input">
      <button
        className={`voice-button ${state.isRecording ? 'listening' : ''}`}
        onClick={handleToggle}
        disabled={disabled || !isActive}
        title={isActive ? 'Click to start voice input' : 'Configure API key to enable voice input'}
      >
        <span className="voice-icon">🎤</span>
        <span className="voice-label">
          {state.isRecording ? 'Listening...' : isActive ? 'Voice Input' : 'Voice (Configure API Key)'}
        </span>
      </button>

      {state.interimTranscript && (
        <div className="interim-transcript">
          <span className="transcript-label">Hearing:</span>
          <span className="transcript-text">{state.interimTranscript}</span>
        </div>
      )}

      {state.error && (
        <div className="voice-error">
          <span className="error-icon">⚠️</span>
          <span className="error-text">{state.error}</span>
        </div>
      )}
    </div>
  );
});

VoiceInput.displayName = 'VoiceInput';
