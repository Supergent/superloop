/**
 * Event bus for voice-related events.
 * Allows decoupled communication between voice components.
 */

import {
  TranscriptEvent,
  PlaybackEvent,
  VoiceActivationState,
  VoiceIntent,
  VoiceError,
} from './types';

export type VoiceEventType =
  | 'transcript:interim'
  | 'transcript:final'
  | 'playback:started'
  | 'playback:paused'
  | 'playback:resumed'
  | 'playback:completed'
  | 'playback:error'
  | 'activation:state-change'
  | 'intent:detected'
  | 'error';

export type VoiceEventPayload =
  | { type: 'transcript:interim'; data: TranscriptEvent }
  | { type: 'transcript:final'; data: TranscriptEvent }
  | { type: 'playback:started'; data: PlaybackEvent }
  | { type: 'playback:paused'; data: PlaybackEvent }
  | { type: 'playback:resumed'; data: PlaybackEvent }
  | { type: 'playback:completed'; data: PlaybackEvent }
  | { type: 'playback:error'; data: PlaybackEvent }
  | { type: 'activation:state-change'; data: { state: VoiceActivationState } }
  | { type: 'intent:detected'; data: VoiceIntent }
  | { type: 'error'; data: VoiceError };

type VoiceEventListener<T extends VoiceEventPayload = VoiceEventPayload> = (
  payload: T
) => void;

/**
 * Simple event bus for voice events.
 */
class VoiceEventBus {
  private listeners: Map<VoiceEventType, Set<VoiceEventListener>> = new Map();

  /**
   * Subscribe to a voice event.
   * @param eventType - The type of event to listen for
   * @param listener - Callback function to invoke when event is emitted
   * @returns Unsubscribe function
   */
  on<T extends VoiceEventPayload>(
    eventType: T['type'],
    listener: VoiceEventListener<T>
  ): () => void {
    if (!this.listeners.has(eventType)) {
      this.listeners.set(eventType, new Set());
    }

    const listeners = this.listeners.get(eventType)!;
    listeners.add(listener as VoiceEventListener);

    // Return unsubscribe function
    return () => {
      listeners.delete(listener as VoiceEventListener);
      if (listeners.size === 0) {
        this.listeners.delete(eventType);
      }
    };
  }

  /**
   * Subscribe to a voice event, but only listen once.
   * Automatically unsubscribes after the first event.
   * @param eventType - The type of event to listen for
   * @param listener - Callback function to invoke when event is emitted
   * @returns Unsubscribe function
   */
  once<T extends VoiceEventPayload>(
    eventType: T['type'],
    listener: VoiceEventListener<T>
  ): () => void {
    const wrappedListener = (payload: T) => {
      listener(payload);
      unsubscribe();
    };

    const unsubscribe = this.on(eventType, wrappedListener as VoiceEventListener<T>);
    return unsubscribe;
  }

  /**
   * Emit a voice event to all subscribers.
   * @param payload - Event payload containing type and data
   */
  emit<T extends VoiceEventPayload>(payload: T): void {
    const listeners = this.listeners.get(payload.type);
    if (!listeners) return;

    listeners.forEach(listener => {
      try {
        listener(payload);
      } catch (error) {
        console.error(`Error in voice event listener for ${payload.type}:`, error);
      }
    });
  }

  /**
   * Remove all listeners for a specific event type, or all listeners if no type specified.
   * @param eventType - Optional event type to clear listeners for
   */
  clear(eventType?: VoiceEventType): void {
    if (eventType) {
      this.listeners.delete(eventType);
    } else {
      this.listeners.clear();
    }
  }

  /**
   * Get the number of listeners for a specific event type.
   * @param eventType - Event type to count listeners for
   * @returns Number of listeners
   */
  listenerCount(eventType: VoiceEventType): number {
    return this.listeners.get(eventType)?.size ?? 0;
  }
}

// Export singleton instance
export const voiceEventBus = new VoiceEventBus();

// Export helper functions for common events

/**
 * Emit an interim transcript event
 */
export function emitInterimTranscript(transcript: TranscriptEvent): void {
  voiceEventBus.emit({ type: 'transcript:interim', data: transcript });
}

/**
 * Emit a final transcript event
 */
export function emitFinalTranscript(transcript: TranscriptEvent): void {
  voiceEventBus.emit({ type: 'transcript:final', data: transcript });
}

/**
 * Emit a playback event
 */
export function emitPlaybackEvent(playback: PlaybackEvent): void {
  const eventType = `playback:${playback.type}` as VoiceEventType;
  voiceEventBus.emit({ type: eventType, data: playback } as VoiceEventPayload);
}

/**
 * Emit an activation state change event
 */
export function emitActivationStateChange(state: VoiceActivationState): void {
  voiceEventBus.emit({ type: 'activation:state-change', data: { state } });
}

/**
 * Emit a voice intent detection event
 */
export function emitVoiceIntent(intent: VoiceIntent): void {
  voiceEventBus.emit({ type: 'intent:detected', data: intent });
}

/**
 * Emit a voice error event
 */
export function emitVoiceError(error: VoiceError): void {
  voiceEventBus.emit({ type: 'error', data: error });
}
