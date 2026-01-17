/**
 * React hook for Claude Agent SDK integration
 * Manages session IDs and streams responses for UI/TTS consumers
 */

import { useState, useCallback, useRef } from 'react';
import type { StreamMessage } from '@anthropic-ai/claude-agent-sdk';
import { queryAgent, configureAgent, type AgentConfig } from '../lib/agent';

// ============================================================================
// Types
// ============================================================================

export interface AgentMessage {
  id: string;
  type: 'user' | 'assistant' | 'error';
  content: string;
  timestamp: Date;
}

export interface AgentStreamEvent {
  type: StreamMessage['type'];
  content: string;
  timestamp: Date;
}

interface UseClaudeAgentState {
  messages: AgentMessage[];
  streaming: boolean;
  error: Error | null;
  sessionId: string | null;
}

interface UseClaudeAgentActions {
  // Send a message to the agent
  sendMessage: (prompt: string, options?: SendMessageOptions) => Promise<void>;

  // Configure the agent
  configure: (config: AgentConfig) => void;

  // Reset the conversation
  reset: () => void;

  // Clear messages but keep session
  clearMessages: () => void;
}

export interface SendMessageOptions {
  onStreamEvent?: (event: AgentStreamEvent) => void;
  onTextChunk?: (text: string) => void;
  onComplete?: (fullText: string) => void;
}

export interface UseClaudeAgentResult {
  state: UseClaudeAgentState;
  actions: UseClaudeAgentActions;
}

// ============================================================================
// Helper Functions
// ============================================================================

function generateMessageId(): string {
  return `msg_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
}

function generateSessionId(): string {
  return `session_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
}

// ============================================================================
// Hook
// ============================================================================

export function useClaudeAgent(): UseClaudeAgentResult {
  // State
  const [state, setState] = useState<UseClaudeAgentState>({
    messages: [],
    streaming: false,
    error: null,
    sessionId: null,
  });

  // Ref to track if a stream is in progress (for cleanup)
  const streamingRef = useRef(false);

  // ============================================================================
  // Actions
  // ============================================================================

  const sendMessage = useCallback(
    async (prompt: string, options?: SendMessageOptions) => {
      // Don't allow multiple simultaneous streams
      if (streamingRef.current) {
        console.warn('Already streaming a response');
        return;
      }

      try {
        streamingRef.current = true;

        // Generate or reuse session ID
        const sessionId = state.sessionId || generateSessionId();

        // Add user message
        const userMessage: AgentMessage = {
          id: generateMessageId(),
          type: 'user',
          content: prompt,
          timestamp: new Date(),
        };

        setState((prev) => ({
          ...prev,
          messages: [...prev.messages, userMessage],
          streaming: true,
          error: null,
          sessionId,
        }));

        // Collect assistant response text
        let assistantText = '';
        const textChunks: string[] = [];

        // Stream the response
        for await (const message of queryAgent({
          prompt,
          sessionId,
          onError: (error) => {
            setState((prev) => ({
              ...prev,
              streaming: false,
              error,
            }));
          },
        })) {
          // Create stream event
          const event: AgentStreamEvent = {
            type: message.type,
            content: message.type === 'text' ? message.text : JSON.stringify(message),
            timestamp: new Date(),
          };

          // Call stream event handler
          if (options?.onStreamEvent) {
            options.onStreamEvent(event);
          }

          // Handle text messages
          if (message.type === 'text') {
            textChunks.push(message.text);
            assistantText += message.text;

            // Call text chunk handler
            if (options?.onTextChunk) {
              options.onTextChunk(message.text);
            }
          }
        }

        // Add assistant message
        const assistantMessage: AgentMessage = {
          id: generateMessageId(),
          type: 'assistant',
          content: assistantText,
          timestamp: new Date(),
        };

        setState((prev) => ({
          ...prev,
          messages: [...prev.messages, assistantMessage],
          streaming: false,
        }));

        // Call completion handler
        if (options?.onComplete) {
          options.onComplete(assistantText);
        }
      } catch (error) {
        const err = error instanceof Error ? error : new Error(String(error));

        // Add error message
        const errorMessage: AgentMessage = {
          id: generateMessageId(),
          type: 'error',
          content: err.message,
          timestamp: new Date(),
        };

        setState((prev) => ({
          ...prev,
          messages: [...prev.messages, errorMessage],
          streaming: false,
          error: err,
        }));
      } finally {
        streamingRef.current = false;
      }
    },
    [state.sessionId]
  );

  const configure = useCallback((config: AgentConfig) => {
    configureAgent(config);
  }, []);

  const reset = useCallback(() => {
    setState({
      messages: [],
      streaming: false,
      error: null,
      sessionId: null,
    });
  }, []);

  const clearMessages = useCallback(() => {
    setState((prev) => ({
      ...prev,
      messages: [],
      error: null,
    }));
  }, []);

  // ============================================================================
  // Return
  // ============================================================================

  return {
    state,
    actions: {
      sendMessage,
      configure,
      reset,
      clearMessages,
    },
  };
}

// ============================================================================
// Convenience Hooks
// ============================================================================

/**
 * Hook for simple text-only interactions (no message history)
 */
export function useClaudeAgentSimple() {
  const [response, setResponse] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<Error | null>(null);

  const query = useCallback(async (prompt: string) => {
    setLoading(true);
    setError(null);
    setResponse(null);

    let fullText = '';

    try {
      for await (const message of queryAgent({ prompt })) {
        if (message.type === 'text') {
          fullText += message.text;
        }
      }

      setResponse(fullText);
      return fullText;
    } catch (err) {
      const error = err instanceof Error ? err : new Error(String(err));
      setError(error);
      return null;
    } finally {
      setLoading(false);
    }
  }, []);

  return {
    query,
    response,
    loading,
    error,
    reset: () => {
      setResponse(null);
      setError(null);
    },
  };
}

export default useClaudeAgent;
