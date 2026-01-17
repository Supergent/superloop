import { useState, useRef, useCallback, useEffect } from 'react';
import { emitPlaybackEvent } from '../lib/voice/events';
import type { PlaybackEvent } from '../lib/voice/types';

export interface VapiTtsConfig {
  publicKey: string;
  voice?: string;
  model?: string;
}

export interface VapiTtsState {
  isPlaying: boolean;
  isPaused: boolean;
  isMuted: boolean;
  error: string | null;
  currentText: string | null;
}

export interface VapiTtsActions {
  speak: (text: string) => Promise<void>;
  pause: () => void;
  resume: () => void;
  stop: () => void;
  mute: () => void;
  unmute: () => void;
}

/**
 * Hook for text-to-speech using Vapi.
 *
 * @param config - Vapi configuration including public key
 * @param onPlaybackEvent - Optional callback for playback events
 * @returns State and actions for controlling TTS
 */
export function useVapiTts(
  config: VapiTtsConfig,
  onPlaybackEvent?: (event: PlaybackEvent) => void
): [VapiTtsState, VapiTtsActions] {
  const [state, setState] = useState<VapiTtsState>({
    isPlaying: false,
    isPaused: false,
    isMuted: false,
    error: null,
    currentText: null,
  });

  const audioRef = useRef<HTMLAudioElement | null>(null);
  const audioContextRef = useRef<AudioContext | null>(null);
  const gainNodeRef = useRef<GainNode | null>(null);
  const currentTextRef = useRef<string | null>(null);

  // Initialize audio context for muting
  useEffect(() => {
    if (typeof window !== 'undefined' && !audioContextRef.current) {
      audioContextRef.current = new (window.AudioContext || (window as any).webkitAudioContext)();
      gainNodeRef.current = audioContextRef.current.createGain();
    }

    return () => {
      if (audioContextRef.current) {
        audioContextRef.current.close();
      }
    };
  }, []);

  // Helper to emit and callback
  const emitEvent = useCallback((event: PlaybackEvent) => {
    emitPlaybackEvent(event);
    onPlaybackEvent?.(event);
  }, [onPlaybackEvent]);

  // Speak text using Vapi
  const speak = useCallback(async (text: string) => {
    try {
      // Stop any existing audio before starting new playback
      if (audioRef.current) {
        audioRef.current.pause();
        audioRef.current.currentTime = 0;
        audioRef.current = null;
      }

      currentTextRef.current = text;
      setState(prev => ({ ...prev, error: null, currentText: text }));

      // Call Vapi TTS API to get audio URL
      const response = await fetch('https://api.vapi.ai/v1/tts', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${config.publicKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          text,
          voice: config.voice || 'en-US-Neural2-J',
          model: config.model || 'tts-1',
        }),
      });

      if (!response.ok) {
        throw new Error(`Vapi API error: ${response.statusText}`);
      }

      const data = await response.json();
      const audioUrl = data.audio_url || data.url;

      if (!audioUrl) {
        throw new Error('No audio URL returned from Vapi');
      }

      // Create and play audio
      const audio = new Audio(audioUrl);
      audioRef.current = audio;

      // Set up audio context for muting if needed
      if (audioContextRef.current && gainNodeRef.current) {
        const source = audioContextRef.current.createMediaElementSource(audio);
        source.connect(gainNodeRef.current);
        gainNodeRef.current.connect(audioContextRef.current.destination);
      }

      audio.onplay = () => {
        setState(prev => ({ ...prev, isPlaying: true, isPaused: false }));
        emitEvent({
          type: 'started',
          text,
          timestamp: Date.now(),
        });
      };

      audio.onpause = () => {
        setState(prev => ({ ...prev, isPaused: true }));
        emitEvent({
          type: 'paused',
          text,
          timestamp: Date.now(),
        });
      };

      audio.onended = () => {
        setState(prev => ({
          ...prev,
          isPlaying: false,
          isPaused: false,
          currentText: null,
        }));
        emitEvent({
          type: 'completed',
          text,
          timestamp: Date.now(),
        });
        audioRef.current = null;
      };

      audio.onerror = () => {
        const error = 'Audio playback failed';
        setState(prev => ({
          ...prev,
          isPlaying: false,
          isPaused: false,
          error,
          currentText: null,
        }));
        emitEvent({
          type: 'error',
          text,
          error,
          timestamp: Date.now(),
        });
        audioRef.current = null;
      };

      await audio.play();

    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown TTS error';
      setState(prev => ({
        ...prev,
        isPlaying: false,
        isPaused: false,
        error: errorMessage,
        currentText: null,
      }));
      emitEvent({
        type: 'error',
        text,
        error: errorMessage,
        timestamp: Date.now(),
      });
    }
  }, [config.publicKey, config.voice, config.model, emitEvent]);

  // Pause playback
  const pause = useCallback(() => {
    if (audioRef.current && !audioRef.current.paused) {
      audioRef.current.pause();
    }
  }, []);

  // Resume playback
  const resume = useCallback(() => {
    if (audioRef.current && audioRef.current.paused) {
      audioRef.current.play();
      setState(prev => ({ ...prev, isPaused: false, isPlaying: true }));
      emitEvent({
        type: 'resumed',
        text: currentTextRef.current || undefined,
        timestamp: Date.now(),
      });
    }
  }, [emitEvent]);

  // Stop playback
  const stop = useCallback(() => {
    if (audioRef.current) {
      const currentText = currentTextRef.current;
      // Remove onpause handler to prevent it from setting isPaused=true during stop
      audioRef.current.onpause = null;
      audioRef.current.pause();
      audioRef.current.currentTime = 0;
      currentTextRef.current = null;
      setState(prev => ({
        ...prev,
        isPlaying: false,
        isPaused: false,
        currentText: null,
      }));
      emitEvent({
        type: 'stopped',
        text: currentText || undefined,
        timestamp: Date.now(),
      });
      audioRef.current = null;
    }
  }, [emitEvent]);

  // Mute audio
  const mute = useCallback(() => {
    if (gainNodeRef.current) {
      gainNodeRef.current.gain.value = 0;
      setState(prev => ({ ...prev, isMuted: true }));
    } else if (audioRef.current) {
      audioRef.current.muted = true;
      setState(prev => ({ ...prev, isMuted: true }));
    }
  }, []);

  // Unmute audio
  const unmute = useCallback(() => {
    if (gainNodeRef.current) {
      gainNodeRef.current.gain.value = 1;
      setState(prev => ({ ...prev, isMuted: false }));
    } else if (audioRef.current) {
      audioRef.current.muted = false;
      setState(prev => ({ ...prev, isMuted: false }));
    }
  }, []);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (audioRef.current) {
        audioRef.current.pause();
        audioRef.current = null;
      }
    };
  }, []);

  return [
    state,
    {
      speak,
      pause,
      resume,
      stop,
      mute,
      unmute,
    },
  ];
}
