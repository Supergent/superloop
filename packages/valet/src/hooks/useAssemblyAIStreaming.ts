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
  const mediaStreamRef = useRef<MediaStream | null>(null);
  const audioContextRef = useRef<AudioContext | null>(null);
  const processorRef = useRef<ScriptProcessorNode | null>(null);

  // Cleanup function
  const cleanup = useCallback(() => {
    // Stop audio processing
    if (processorRef.current) {
      processorRef.current.disconnect();
      processorRef.current = null;
    }
    if (audioContextRef.current) {
      audioContextRef.current.close();
      audioContextRef.current = null;
    }

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

      // Create AudioContext first to determine actual sample rate
      // On macOS/WebKit, the browser may ignore the requested sample rate
      // and use the hardware's default (typically 44.1kHz or 48kHz)
      const requestedSampleRate = config.sampleRate || 16000;
      const audioContext = new AudioContext({ sampleRate: requestedSampleRate });
      audioContextRef.current = audioContext;

      // Use the actual sample rate from AudioContext (may differ from requested)
      const sampleRate = audioContext.sampleRate;

      // Create WebSocket connection to AssemblyAI (Universal-Streaming v3)
      // v3 uses different parameters than v2:
      // - encoding: audio format (pcm_s16le or pcm_mulaw)
      // - min_end_of_turn_silence_when_confident: silence when semantic model is confident
      // - max_turn_silence: maximum silence before triggering end of turn
      // - end_of_turn_confidence_threshold: controls semantic vs acoustic detection
      const encoding = config.encoding || 'pcm_s16le';
      const silenceThreshold = config.endUtteranceSilenceThreshold || 2000;
      const confidenceThreshold = silenceThreshold >= 3000 ? 0.7 : 0.4;

      const ws = new WebSocket(
        `wss://streaming.assemblyai.com/v3/ws?sample_rate=${sampleRate}&encoding=${encoding}&min_end_of_turn_silence_when_confident=${silenceThreshold}&max_turn_silence=${silenceThreshold}&end_of_turn_confidence_threshold=${confidenceThreshold}&token=${config.apiKey}`
      );
      wsRef.current = ws;

      ws.onopen = () => {
        setState(prev => ({ ...prev, isConnected: true, isRecording: true }));

        const source = audioContext.createMediaStreamSource(stream);
        const processor = audioContext.createScriptProcessor(4096, 1, 1);
        processorRef.current = processor;

        processor.onaudioprocess = (e) => {
          // Only send audio if WebSocket is open
          if (ws.readyState !== WebSocket.OPEN) return;

          const inputData = e.inputBuffer.getChannelData(0);

          // Convert Float32Array to Int16Array (PCM s16le)
          const pcmData = new Int16Array(inputData.length);
          for (let i = 0; i < inputData.length; i++) {
            // Clamp to [-1, 1] and convert to 16-bit integer
            const s = Math.max(-1, Math.min(1, inputData[i]));
            pcmData[i] = s < 0 ? s * 0x8000 : s * 0x7fff;
          }

          // Send binary PCM data to WebSocket
          ws.send(pcmData.buffer);
        };

        source.connect(processor);
        processor.connect(audioContext.destination);

        // Emit activation state change
        emitActivationStateChange('listening');
      };

      ws.onmessage = (event) => {
        const data = JSON.parse(event.data);

        if (data.type === 'Begin') {
          // Session started message
          console.log('AssemblyAI session started:', data.id, 'expires:', data.expires_at);
        } else if (data.type === 'Turn' && data.transcript) {
          // Universal-Streaming uses immutable Turn messages
          // end_of_turn=true means this is a complete utterance (like FinalTranscript)
          // end_of_turn=false means more words coming (like PartialTranscript)
          const isFinal = data.end_of_turn === true;
          const confidence = data.end_of_turn_confidence || 0;

          const transcript: TranscriptEvent = {
            text: data.transcript,
            isFinal,
            confidence,
          };

          if (isFinal) {
            setState(prev => ({
              ...prev,
              finalTranscript: prev.finalTranscript + ' ' + data.transcript,
              interimTranscript: '',
            }));

            // Emit final transcript event
            emitFinalTranscript(transcript);
            // Emit processing state after final transcript
            emitActivationStateChange('processing');
            onFinalTranscript?.(transcript);
          } else {
            setState(prev => ({
              ...prev,
              interimTranscript: data.transcript,
            }));

            // Emit interim transcript event
            emitInterimTranscript(transcript);
            onInterimTranscript?.(transcript);
          }
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
        // Invoke cleanup to stop audio processing/MediaStream and reset state
        cleanup();

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
  }, [config.apiKey, config.sampleRate, config.encoding, config.endUtteranceSilenceThreshold, onInterimTranscript, onFinalTranscript, onError, cleanup]);

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
