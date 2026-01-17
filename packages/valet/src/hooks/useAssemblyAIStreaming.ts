import { useState, useEffect, useRef, useCallback } from 'react';
import {
  emitInterimTranscript,
  emitFinalTranscript,
  emitActivationStateChange,
  emitVoiceError,
} from '../lib/voice/events';

export interface TranscriptEvent {
  text: string;
  isFinal: boolean;
  confidence?: number;
}

export interface AssemblyAIStreamingConfig {
  apiKey: string;
  sampleRate?: number;
  encoding?: 'pcm_s16le' | 'pcm_mulaw';
  endUtteranceSilenceThreshold?: number;
}

export interface AssemblyAIStreamingState {
  isConnected: boolean;
  isRecording: boolean;
  error: string | null;
  interimTranscript: string;
  finalTranscript: string;
}

export interface AssemblyAIStreamingActions {
  start: () => Promise<void>;
  stop: () => void;
  reset: () => void;
}

/**
 * Hook for real-time speech-to-text using AssemblyAI streaming API.
 *
 * @param config - AssemblyAI configuration including API key
 * @param onInterimTranscript - Callback for interim transcripts (real-time updates)
 * @param onFinalTranscript - Callback for final transcripts (complete utterances)
 * @param onError - Callback for errors
 * @returns State and actions for controlling the stream
 */
export function useAssemblyAIStreaming(
  config: AssemblyAIStreamingConfig,
  onInterimTranscript?: (event: TranscriptEvent) => void,
  onFinalTranscript?: (event: TranscriptEvent) => void,
  onError?: (error: Error) => void
): [AssemblyAIStreamingState, AssemblyAIStreamingActions] {
  const [state, setState] = useState<AssemblyAIStreamingState>({
    isConnected: false,
    isRecording: false,
    error: null,
    interimTranscript: '',
    finalTranscript: '',
  });

  const wsRef = useRef<WebSocket | null>(null);
  const mediaRecorderRef = useRef<MediaRecorder | null>(null);
  const mediaStreamRef = useRef<MediaStream | null>(null);

  // Cleanup function
  const cleanup = useCallback(() => {
    // Stop media recorder
    if (mediaRecorderRef.current && mediaRecorderRef.current.state !== 'inactive') {
      mediaRecorderRef.current.stop();
    }
    mediaRecorderRef.current = null;

    // Stop media stream tracks
    if (mediaStreamRef.current) {
      mediaStreamRef.current.getTracks().forEach(track => track.stop());
    }
    mediaStreamRef.current = null;

    // Close websocket
    if (wsRef.current && wsRef.current.readyState !== WebSocket.CLOSED) {
      wsRef.current.close();
    }
    wsRef.current = null;

    setState(prev => ({
      ...prev,
      isConnected: false,
      isRecording: false,
    }));
  }, []);

  // Start streaming
  const start = useCallback(async () => {
    try {
      setState(prev => ({ ...prev, error: null }));

      // Get microphone access
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      mediaStreamRef.current = stream;

      // Create WebSocket connection to AssemblyAI
      const ws = new WebSocket(
        `wss://api.assemblyai.com/v2/realtime/ws?sample_rate=${config.sampleRate || 16000}`
      );
      wsRef.current = ws;

      ws.onopen = () => {
        setState(prev => ({ ...prev, isConnected: true }));

        // Send authentication token
        ws.send(JSON.stringify({
          audio_data: null,
          token: config.apiKey,
        }));

        // Start recording
        const mediaRecorder = new MediaRecorder(stream, {
          mimeType: 'audio/webm',
        });
        mediaRecorderRef.current = mediaRecorder;

        mediaRecorder.ondataavailable = (event) => {
          if (event.data.size > 0 && ws.readyState === WebSocket.OPEN) {
            // Convert blob to base64 and send to AssemblyAI
            const reader = new FileReader();
            reader.onloadend = () => {
              const base64Audio = (reader.result as string).split(',')[1];
              ws.send(JSON.stringify({ audio_data: base64Audio }));
            };
            reader.readAsDataURL(event.data);
          }
        };

        mediaRecorder.start(100); // Send data every 100ms
        setState(prev => ({ ...prev, isRecording: true }));

        // Emit activation state change
        emitActivationStateChange('listening');
      };

      ws.onmessage = (event) => {
        const data = JSON.parse(event.data);

        if (data.message_type === 'PartialTranscript') {
          const transcript: TranscriptEvent = {
            text: data.text,
            isFinal: false,
            confidence: data.confidence,
          };

          setState(prev => ({
            ...prev,
            interimTranscript: data.text,
          }));

          // Emit interim transcript event
          emitInterimTranscript(transcript);
          onInterimTranscript?.(transcript);
        } else if (data.message_type === 'FinalTranscript') {
          const transcript: TranscriptEvent = {
            text: data.text,
            isFinal: true,
            confidence: data.confidence,
          };

          setState(prev => ({
            ...prev,
            finalTranscript: prev.finalTranscript + ' ' + data.text,
            interimTranscript: '',
          }));

          // Emit final transcript event
          emitFinalTranscript(transcript);
          // Emit processing state after final transcript
          emitActivationStateChange('processing');
          onFinalTranscript?.(transcript);
        } else if (data.message_type === 'SessionBegins') {
          console.log('AssemblyAI session started:', data);
        }
      };

      ws.onerror = (error) => {
        const err = new Error('WebSocket error occurred');
        setState(prev => ({
          ...prev,
          error: err.message,
          isConnected: false,
          isRecording: false,
        }));

        // Emit error event
        emitVoiceError({
          type: 'connection_error',
          message: err.message,
          source: 'assemblyai',
        });
        emitActivationStateChange('idle');

        onError?.(err);
        cleanup();
      };

      ws.onclose = () => {
        setState(prev => ({
          ...prev,
          isConnected: false,
          isRecording: false,
        }));

        // Emit idle state when connection closes
        emitActivationStateChange('idle');
      };

    } catch (error) {
      const err = error instanceof Error ? error : new Error('Failed to start streaming');
      setState(prev => ({
        ...prev,
        error: err.message,
        isConnected: false,
        isRecording: false,
      }));

      // Emit error event
      emitVoiceError({
        type: 'microphone_error',
        message: err.message,
        source: 'assemblyai',
      });
      emitActivationStateChange('idle');

      onError?.(err);
      cleanup();
    }
  }, [config.apiKey, config.sampleRate, onInterimTranscript, onFinalTranscript, onError, cleanup]);

  // Stop streaming
  const stop = useCallback(() => {
    // Send terminate message to AssemblyAI
    if (wsRef.current && wsRef.current.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify({ terminate_session: true }));
    }
    cleanup();

    // Emit idle state when stopping
    emitActivationStateChange('idle');
  }, [cleanup]);

  // Reset transcripts
  const reset = useCallback(() => {
    setState(prev => ({
      ...prev,
      interimTranscript: '',
      finalTranscript: '',
      error: null,
    }));
  }, []);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      cleanup();
    };
  }, [cleanup]);

  return [
    state,
    {
      start,
      stop,
      reset,
    },
  ];
}
