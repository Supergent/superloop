import { renderHook, act, waitFor } from '@testing-library/react';
import { useVapiTts } from '../useVapiTts';
import * as voiceEvents from '../../lib/voice/events';

// Mock voice events
jest.mock('../../lib/voice/events', () => ({
  emitPlaybackEvent: jest.fn(),
}));

// Mock Audio
class MockAudio {
  src: string = '';
  paused: boolean = true;
  currentTime: number = 0;
  muted: boolean = false;
  onplay: (() => void) | null = null;
  onpause: (() => void) | null = null;
  onended: (() => void) | null = null;
  onerror: (() => void) | null = null;

  constructor(src?: string) {
    if (src) {
      this.src = src;
    }
  }

  play = jest.fn(() => {
    this.paused = false;
    this.onplay?.();
    return Promise.resolve();
  });

  pause = jest.fn(() => {
    this.paused = true;
    this.onpause?.();
  });
}

global.Audio = MockAudio as any;

// Mock AudioContext
class MockGainNode {
  gain = { value: 1 };
  connect = jest.fn();
}

class MockMediaElementSource {
  connect = jest.fn();
}

class MockAudioContext {
  destination = {};
  createGain = jest.fn(() => new MockGainNode());
  createMediaElementSource = jest.fn(() => new MockMediaElementSource());
  close = jest.fn();
}

(global as any).AudioContext = MockAudioContext;
(global as any).webkitAudioContext = MockAudioContext;

// Mock fetch
global.fetch = jest.fn();

describe('useVapiTts', () => {
  const mockConfig = {
    publicKey: 'test-public-key',
    voice: 'test-voice',
    model: 'tts-1',
  };

  beforeEach(() => {
    jest.clearAllMocks();
    (global.fetch as jest.Mock).mockResolvedValue({
      ok: true,
      json: async () => ({ audio_url: 'https://example.com/audio.mp3' }),
    });
  });

  describe('pause/resume/mute states', () => {
    it('should pause playback when pause is called', async () => {
      const { result } = renderHook(() => useVapiTts(mockConfig));

      const [, actions] = result.current;

      // Start speaking
      await act(async () => {
        await actions.speak('Hello world');
      });

      const [stateBeforePause] = result.current;
      expect(stateBeforePause.isPlaying).toBe(true);
      expect(stateBeforePause.isPaused).toBe(false);

      // Pause
      act(() => {
        actions.pause();
      });

      // Verify pause was called on audio
      const mockAudio = (global.Audio as any).mock.results[0].value;
      expect(mockAudio.pause).toHaveBeenCalled();
    });

    it('should resume playback when resume is called', async () => {
      const { result } = renderHook(() => useVapiTts(mockConfig));

      const [, actions] = result.current;

      // Start speaking
      await act(async () => {
        await actions.speak('Hello world');
      });

      // Pause
      act(() => {
        actions.pause();
      });

      // Get the mock audio instance
      const mockAudio = (global.Audio as any).mock.results[0].value;
      mockAudio.paused = true;

      // Resume
      await act(async () => {
        actions.resume();
      });

      expect(mockAudio.play).toHaveBeenCalledTimes(2); // Once for speak, once for resume

      const [stateAfterResume] = result.current;
      expect(stateAfterResume.isPaused).toBe(false);
      expect(stateAfterResume.isPlaying).toBe(true);
    });

    it('should mute audio when mute is called', async () => {
      const { result } = renderHook(() => useVapiTts(mockConfig));

      const [, actions] = result.current;

      // Start speaking
      await act(async () => {
        await actions.speak('Hello world');
      });

      // Mute
      act(() => {
        actions.mute();
      });

      const [stateAfterMute] = result.current;
      expect(stateAfterMute.isMuted).toBe(true);
    });

    it('should unmute audio when unmute is called', async () => {
      const { result } = renderHook(() => useVapiTts(mockConfig));

      const [, actions] = result.current;

      // Start speaking
      await act(async () => {
        await actions.speak('Hello world');
      });

      // Mute then unmute
      act(() => {
        actions.mute();
      });

      act(() => {
        actions.unmute();
      });

      const [stateAfterUnmute] = result.current;
      expect(stateAfterUnmute.isMuted).toBe(false);
    });

    it('should stop playback when stop is called', async () => {
      const { result } = renderHook(() => useVapiTts(mockConfig));

      const [, actions] = result.current;

      // Start speaking
      await act(async () => {
        await actions.speak('Hello world');
      });

      const [stateBeforeStop] = result.current;
      expect(stateBeforeStop.isPlaying).toBe(true);

      // Stop
      act(() => {
        actions.stop();
      });

      const [stateAfterStop] = result.current;
      expect(stateAfterStop.isPlaying).toBe(false);
      expect(stateAfterStop.isPaused).toBe(false);
      expect(stateAfterStop.currentText).toBe(null);
    });
  });

  describe('playback events', () => {
    it('should emit started event when playback begins', async () => {
      const { result } = renderHook(() => useVapiTts(mockConfig));

      const [, actions] = result.current;

      await act(async () => {
        await actions.speak('Hello world');
      });

      expect(voiceEvents.emitPlaybackEvent).toHaveBeenCalledWith({
        type: 'started',
        text: 'Hello world',
        timestamp: expect.any(Number),
      });
    });

    it('should emit paused event when playback is paused', async () => {
      const { result } = renderHook(() => useVapiTts(mockConfig));

      const [, actions] = result.current;

      await act(async () => {
        await actions.speak('Hello world');
      });

      // Clear previous calls
      jest.clearAllMocks();

      // Get the mock audio instance and simulate pause event
      const mockAudio = (global.Audio as any).mock.results[0].value;

      act(() => {
        actions.pause();
        mockAudio.onpause?.();
      });

      expect(voiceEvents.emitPlaybackEvent).toHaveBeenCalledWith({
        type: 'paused',
        text: 'Hello world',
        timestamp: expect.any(Number),
      });
    });

    it('should emit completed event when playback ends', async () => {
      const { result } = renderHook(() => useVapiTts(mockConfig));

      const [, actions] = result.current;

      await act(async () => {
        await actions.speak('Hello world');
      });

      // Get the mock audio instance and simulate end event
      const mockAudio = (global.Audio as any).mock.results[0].value;

      act(() => {
        mockAudio.onended?.();
      });

      expect(voiceEvents.emitPlaybackEvent).toHaveBeenCalledWith({
        type: 'completed',
        text: 'Hello world',
        timestamp: expect.any(Number),
      });

      const [stateAfterEnd] = result.current;
      expect(stateAfterEnd.isPlaying).toBe(false);
      expect(stateAfterEnd.currentText).toBe(null);
    });

    it('should emit resumed event when playback resumes', async () => {
      const { result } = renderHook(() => useVapiTts(mockConfig));

      const [, actions] = result.current;

      await act(async () => {
        await actions.speak('Hello world');
      });

      act(() => {
        actions.pause();
      });

      // Clear previous calls
      jest.clearAllMocks();

      const mockAudio = (global.Audio as any).mock.results[0].value;
      mockAudio.paused = true;

      await act(async () => {
        actions.resume();
      });

      expect(voiceEvents.emitPlaybackEvent).toHaveBeenCalledWith({
        type: 'resumed',
        text: 'Hello world',
        timestamp: expect.any(Number),
      });
    });
  });

  describe('error handling', () => {
    it('should handle API errors', async () => {
      (global.fetch as jest.Mock).mockResolvedValue({
        ok: false,
        statusText: 'Unauthorized',
      });

      const { result } = renderHook(() => useVapiTts(mockConfig));

      const [, actions] = result.current;

      await act(async () => {
        await actions.speak('Hello world');
      });

      const [state] = result.current;
      expect(state.error).toContain('Unauthorized');
      expect(state.isPlaying).toBe(false);
    });

    it('should emit error event on playback failure', async () => {
      const { result } = renderHook(() => useVapiTts(mockConfig));

      const [, actions] = result.current;

      await act(async () => {
        await actions.speak('Hello world');
      });

      // Get the mock audio instance and simulate error event
      const mockAudio = (global.Audio as any).mock.results[0].value;

      act(() => {
        mockAudio.onerror?.();
      });

      expect(voiceEvents.emitPlaybackEvent).toHaveBeenCalledWith({
        type: 'error',
        text: 'Hello world',
        error: 'Audio playback failed',
        timestamp: expect.any(Number),
      });

      const [state] = result.current;
      expect(state.error).toBe('Audio playback failed');
      expect(state.isPlaying).toBe(false);
    });

    it('should handle missing audio URL', async () => {
      (global.fetch as jest.Mock).mockResolvedValue({
        ok: true,
        json: async () => ({}),
      });

      const { result } = renderHook(() => useVapiTts(mockConfig));

      const [, actions] = result.current;

      await act(async () => {
        await actions.speak('Hello world');
      });

      const [state] = result.current;
      expect(state.error).toContain('No audio URL');
      expect(state.isPlaying).toBe(false);
    });
  });

  describe('API integration', () => {
    it('should call Vapi API with correct parameters', async () => {
      const { result } = renderHook(() => useVapiTts(mockConfig));

      const [, actions] = result.current;

      await act(async () => {
        await actions.speak('Hello world');
      });

      expect(global.fetch).toHaveBeenCalledWith(
        'https://api.vapi.ai/v1/tts',
        {
          method: 'POST',
          headers: {
            'Authorization': 'Bearer test-public-key',
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            text: 'Hello world',
            voice: 'test-voice',
            model: 'tts-1',
          }),
        }
      );
    });

    it('should use default voice and model if not specified', async () => {
      const minimalConfig = { publicKey: 'test-key' };
      const { result } = renderHook(() => useVapiTts(minimalConfig));

      const [, actions] = result.current;

      await act(async () => {
        await actions.speak('Hello world');
      });

      expect(global.fetch).toHaveBeenCalledWith(
        'https://api.vapi.ai/v1/tts',
        expect.objectContaining({
          body: JSON.stringify({
            text: 'Hello world',
            voice: 'default',
            model: 'tts-1',
          }),
        })
      );
    });
  });
});
