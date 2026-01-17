import { renderHook, act, waitFor } from '@testing-library/react';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { useAssemblyAIStreaming, type TranscriptEvent } from '../useAssemblyAIStreaming';
import * as voiceEvents from '../../lib/voice/events';

// Mock voice events
vi.mock('../../lib/voice/events', () => ({
  emitInterimTranscript: vi.fn(),
  emitFinalTranscript: vi.fn(),
  emitActivationStateChange: vi.fn(),
  emitVoiceError: vi.fn(),
}));

// Mock MediaRecorder
const mockMediaRecorder = {
  start: vi.fn(),
  stop: vi.fn(),
  state: 'inactive',
  ondataavailable: null as ((event: any) => void) | null,
};

global.MediaRecorder = vi.fn().mockImplementation(() => mockMediaRecorder) as any;

// Mock MediaStream
const mockMediaStream = {
  getTracks: vi.fn(() => [
    { stop: vi.fn() },
  ]),
};

// Mock getUserMedia
const mockGetUserMedia = vi.fn();
Object.defineProperty(global.navigator, 'mediaDevices', {
  value: {
    getUserMedia: mockGetUserMedia,
  },
  writable: true,
});

// Mock WebSocket
class MockWebSocket {
  readyState = WebSocket.CONNECTING;
  onopen: (() => void) | null = null;
  onmessage: ((event: MessageEvent) => void) | null = null;
  onerror: ((event: Event) => void) | null = null;
  onclose: (() => void) | null = null;

  send = vi.fn();
  close = vi.fn(() => {
    this.readyState = WebSocket.CLOSED;
  });

  simulateOpen() {
    this.readyState = WebSocket.OPEN;
    this.onopen?.();
  }

  simulateMessage(data: any) {
    this.onmessage?.({ data: JSON.stringify(data) } as MessageEvent);
  }

  simulateError() {
    this.onerror?.({} as Event);
  }

  simulateClose() {
    this.readyState = WebSocket.CLOSED;
    this.onclose?.();
  }
}

let mockWsInstance: MockWebSocket | null = null;

global.WebSocket = vi.fn().mockImplementation(() => {
  mockWsInstance = new MockWebSocket();
  return mockWsInstance;
}) as any;

describe('useAssemblyAIStreaming', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockGetUserMedia.mockResolvedValue(mockMediaStream);
    mockMediaRecorder.state = 'inactive';
    mockWsInstance = null;
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  describe('activation events', () => {
    it('should emit listening state when starting', async () => {
      const { result } = renderHook(() =>
        useAssemblyAIStreaming({ apiKey: 'test-key' })
      );

      const [, actions] = result.current;

      await act(async () => {
        await actions.start();
        mockWsInstance!.simulateOpen();
      });

      await waitFor(() => {
        expect(voiceEvents.emitActivationStateChange).toHaveBeenCalledWith('listening');
      });
    });

    it('should emit idle state when stopping', async () => {
      const { result } = renderHook(() =>
        useAssemblyAIStreaming({ apiKey: 'test-key' })
      );

      const [, actions] = result.current;

      await act(async () => {
        await actions.start();
        mockWsInstance!.simulateOpen();
      });

      await act(async () => {
        actions.stop();
      });

      await waitFor(() => {
        expect(voiceEvents.emitActivationStateChange).toHaveBeenCalledWith('idle');
      });
    });

    it('should emit idle state on connection close', async () => {
      const { result } = renderHook(() =>
        useAssemblyAIStreaming({ apiKey: 'test-key' })
      );

      const [, actions] = result.current;

      await act(async () => {
        await actions.start();
        mockWsInstance!.simulateOpen();
      });

      vi.clearAllMocks();

      await act(async () => {
        mockWsInstance!.simulateClose();
      });

      await waitFor(() => {
        expect(voiceEvents.emitActivationStateChange).toHaveBeenCalledWith('idle');
      });
    });
  });

  describe('transcript events', () => {
    it('should emit interim transcript events', async () => {
      const onInterimTranscript = vi.fn();

      const { result } = renderHook(() =>
        useAssemblyAIStreaming({ apiKey: 'test-key' }, onInterimTranscript)
      );

      const [, actions] = result.current;

      await act(async () => {
        await actions.start();
        mockWsInstance!.simulateOpen();
      });

      const partialTranscript = {
        message_type: 'PartialTranscript',
        text: 'hello',
        confidence: 0.85,
      };

      await act(async () => {
        mockWsInstance!.simulateMessage(partialTranscript);
      });

      await waitFor(() => {
        expect(voiceEvents.emitInterimTranscript).toHaveBeenCalledWith({
          text: 'hello',
          isFinal: false,
          confidence: 0.85,
        });
      });

      expect(onInterimTranscript).toHaveBeenCalledWith({
        text: 'hello',
        isFinal: false,
        confidence: 0.85,
      });
    });

    it('should emit final transcript events', async () => {
      const onFinalTranscript = vi.fn();

      const { result } = renderHook(() =>
        useAssemblyAIStreaming({ apiKey: 'test-key' }, undefined, onFinalTranscript)
      );

      const [, actions] = result.current;

      await act(async () => {
        await actions.start();
        mockWsInstance!.simulateOpen();
      });

      const finalTranscript = {
        message_type: 'FinalTranscript',
        text: 'hello world',
        confidence: 0.95,
      };

      await act(async () => {
        mockWsInstance!.simulateMessage(finalTranscript);
      });

      await waitFor(() => {
        expect(voiceEvents.emitFinalTranscript).toHaveBeenCalledWith({
          text: 'hello world',
          isFinal: true,
          confidence: 0.95,
        });
      });

      expect(onFinalTranscript).toHaveBeenCalledWith({
        text: 'hello world',
        isFinal: true,
        confidence: 0.95,
      });
    });

    it('should emit processing state after final transcript', async () => {
      const { result } = renderHook(() =>
        useAssemblyAIStreaming({ apiKey: 'test-key' })
      );

      const [, actions] = result.current;

      await act(async () => {
        await actions.start();
        mockWsInstance!.simulateOpen();
      });

      vi.clearAllMocks();

      const finalTranscript = {
        message_type: 'FinalTranscript',
        text: 'hello world',
        confidence: 0.95,
      };

      await act(async () => {
        mockWsInstance!.simulateMessage(finalTranscript);
      });

      await waitFor(() => {
        expect(voiceEvents.emitActivationStateChange).toHaveBeenCalledWith('processing');
      });
    });

    it('should update state with interim transcript', async () => {
      const { result } = renderHook(() =>
        useAssemblyAIStreaming({ apiKey: 'test-key' })
      );

      const [, actions] = result.current;

      await act(async () => {
        await actions.start();
        mockWsInstance!.simulateOpen();
      });

      const partialTranscript = {
        message_type: 'PartialTranscript',
        text: 'testing',
        confidence: 0.8,
      };

      await act(async () => {
        mockWsInstance!.simulateMessage(partialTranscript);
      });

      await waitFor(() => {
        const [state] = result.current;
        expect(state.interimTranscript).toBe('testing');
      });
    });

    it('should update state with final transcript and clear interim', async () => {
      const { result } = renderHook(() =>
        useAssemblyAIStreaming({ apiKey: 'test-key' })
      );

      const [, actions] = result.current;

      await act(async () => {
        await actions.start();
        mockWsInstance!.simulateOpen();
      });

      // Set interim first
      await act(async () => {
        mockWsInstance!.simulateMessage({
          message_type: 'PartialTranscript',
          text: 'hello',
          confidence: 0.8,
        });
      });

      // Then final
      await act(async () => {
        mockWsInstance!.simulateMessage({
          message_type: 'FinalTranscript',
          text: 'hello world',
          confidence: 0.95,
        });
      });

      await waitFor(() => {
        const [state] = result.current;
        expect(state.finalTranscript).toContain('hello world');
        expect(state.interimTranscript).toBe('');
      });
    });
  });

  describe('error events', () => {
    it('should emit error event on WebSocket error', async () => {
      const onError = vi.fn();

      const { result } = renderHook(() =>
        useAssemblyAIStreaming({ apiKey: 'test-key' }, undefined, undefined, onError)
      );

      const [, actions] = result.current;

      await act(async () => {
        await actions.start();
      });

      await act(async () => {
        mockWsInstance!.simulateError();
      });

      await waitFor(() => {
        expect(voiceEvents.emitVoiceError).toHaveBeenCalledWith({
          type: 'connection_error',
          message: 'WebSocket error occurred',
          source: 'assemblyai',
        });
      });

      expect(voiceEvents.emitActivationStateChange).toHaveBeenCalledWith('idle');
      expect(onError).toHaveBeenCalled();
    });

    it('should emit error event on microphone access failure', async () => {
      mockGetUserMedia.mockRejectedValueOnce(new Error('Permission denied'));

      const onError = vi.fn();

      const { result } = renderHook(() =>
        useAssemblyAIStreaming({ apiKey: 'test-key' }, undefined, undefined, onError)
      );

      const [, actions] = result.current;

      await act(async () => {
        await actions.start();
      });

      await waitFor(() => {
        expect(voiceEvents.emitVoiceError).toHaveBeenCalledWith({
          type: 'microphone_error',
          message: expect.stringContaining('Permission denied'),
          source: 'assemblyai',
        });
      });

      expect(voiceEvents.emitActivationStateChange).toHaveBeenCalledWith('idle');
      expect(onError).toHaveBeenCalled();
    });

    it('should set error state on failure', async () => {
      mockGetUserMedia.mockRejectedValueOnce(new Error('Test error'));

      const { result } = renderHook(() =>
        useAssemblyAIStreaming({ apiKey: 'test-key' })
      );

      const [, actions] = result.current;

      await act(async () => {
        await actions.start();
      });

      await waitFor(() => {
        const [state] = result.current;
        expect(state.error).toBeTruthy();
        expect(state.isConnected).toBe(false);
        expect(state.isRecording).toBe(false);
      });
    });
  });

  describe('state management', () => {
    it('should reset transcripts', async () => {
      const { result } = renderHook(() =>
        useAssemblyAIStreaming({ apiKey: 'test-key' })
      );

      const [, actions] = result.current;

      await act(async () => {
        await actions.start();
        mockWsInstance!.simulateOpen();
      });

      // Add some transcripts
      await act(async () => {
        mockWsInstance!.simulateMessage({
          message_type: 'FinalTranscript',
          text: 'test',
          confidence: 0.9,
        });
      });

      // Reset
      await act(async () => {
        actions.reset();
      });

      await waitFor(() => {
        const [state] = result.current;
        expect(state.interimTranscript).toBe('');
        expect(state.finalTranscript).toBe('');
        expect(state.error).toBeNull();
      });
    });

    it('should cleanup on unmount', async () => {
      const { result, unmount } = renderHook(() =>
        useAssemblyAIStreaming({ apiKey: 'test-key' })
      );

      const [, actions] = result.current;

      await act(async () => {
        await actions.start();
        mockWsInstance!.simulateOpen();
      });

      unmount();

      expect(mockWsInstance!.close).toHaveBeenCalled();
    });
  });
});
