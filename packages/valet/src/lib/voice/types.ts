/**
 * Voice-related type definitions for Valet.
 */

/**
 * Transcript event from AssemblyAI
 */
export interface TranscriptEvent {
  /** The transcribed text */
  text: string;
  /** Whether this is a final transcript (true) or interim (false) */
  isFinal: boolean;
  /** Confidence score (0-1) */
  confidence?: number;
  /** Timestamp when the transcript was created */
  timestamp?: number;
}

/**
 * TTS (Text-to-Speech) playback event
 */
export interface PlaybackEvent {
  /** Type of playback event */
  type: 'started' | 'paused' | 'resumed' | 'stopped' | 'completed' | 'error';
  /** The text being spoken */
  text?: string;
  /** Error message if type is 'error' */
  error?: string;
  /** Timestamp when the event occurred */
  timestamp: number;
}

/**
 * Voice activation state
 */
export type VoiceActivationState = 'idle' | 'listening' | 'processing' | 'speaking';

/**
 * Voice command intent extracted from transcript
 */
export interface VoiceIntent {
  /** The original transcript text */
  transcript: string;
  /** Detected intent type */
  intent?: 'status' | 'clean' | 'optimize' | 'uninstall' | 'analyze' | 'help' | 'unknown';
  /** Extracted entities from the transcript */
  entities?: Record<string, string>;
  /** Confidence in the intent detection */
  confidence?: number;
}

/**
 * Voice error types
 */
export type VoiceErrorType =
  | 'microphone_permission_denied'
  | 'microphone_not_found'
  | 'network_error'
  | 'api_error'
  | 'playback_error'
  | 'unknown_error';

/**
 * Voice error event
 */
export interface VoiceError {
  /** Type of error */
  type: VoiceErrorType;
  /** Error message */
  message: string;
  /** Original error object if available */
  originalError?: Error;
  /** Timestamp when the error occurred */
  timestamp: number;
}
