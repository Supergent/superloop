/**
 * Claude Agent SDK Configuration
 * Configures the agent with llm-proxy URL, tool whitelist, and command validation hooks
 */

import { query, type AgentOptions, type StreamMessage } from '@anthropic-ai/claude-agent-sdk';
import { invoke } from '@tauri-apps/api/core';
import { evaluatePolicy, ConfirmationRequiredError, isDryRun } from './agentPolicy';

// ============================================================================
// Types
// ============================================================================

export interface AgentConfig {
  apiKey?: string;
  llmProxyUrl?: string;
  model?: string;
  systemPrompt?: string;
}

export interface AgentQueryOptions {
  prompt: string;
  sessionId?: string;
  timeout?: number; // Timeout in milliseconds (default: 60000 = 1 minute)
  onMessage?: (message: StreamMessage) => void;
  onError?: (error: Error) => void;
  onTimeout?: () => void;
}

// ============================================================================
// Constants
// ============================================================================

const DEFAULT_LLM_PROXY_URL = 'https://llm-proxy.super.gent';
const DEFAULT_MODEL = 'claude-sonnet-4-20250514';
const DEFAULT_TIMEOUT_MS = 60000; // 1 minute
const DEFAULT_SYSTEM_PROMPT = `You are Valet, a Mac maintenance assistant. You help users maintain their Mac by executing Mole commands safely.

**IMPORTANT SAFETY RULES:**
1. ALWAYS run cleanup commands with --dry-run first
2. ALWAYS explain what will be cleaned/removed before executing
3. ALWAYS ask for explicit confirmation before destructive operations
4. NEVER execute commands other than 'mo' (Mole CLI)
5. Be friendly, clear, and concise in your explanations

Your goal is to make Mac maintenance accessible and safe for non-technical users.`;

// ============================================================================
// Agent Configuration
// ============================================================================

let currentConfig: AgentConfig = {
  llmProxyUrl: DEFAULT_LLM_PROXY_URL,
  model: DEFAULT_MODEL,
  systemPrompt: DEFAULT_SYSTEM_PROMPT,
};

/**
 * Configure the Claude agent with custom settings
 */
export function configureAgent(config: AgentConfig): void {
  currentConfig = { ...currentConfig, ...config };
}

/**
 * Get the current agent configuration
 */
export function getAgentConfig(): Readonly<AgentConfig> {
  return { ...currentConfig };
}

// ============================================================================
// Workspace Management
// ============================================================================

/**
 * Get the workspace path for the Claude agent
 */
async function getWorkspacePath(): Promise<string> {
  try {
    const path = await invoke<string>('workspace_path');
    return path;
  } catch (error) {
    throw new Error(`Failed to get workspace path: ${error}`);
  }
}

// ============================================================================
// Command Validation Hook
// ============================================================================

/**
 * Validates that only 'mo' commands are executed via Bash tool
 * This is a critical security measure to prevent arbitrary command execution
 * Also enforces safety policy for destructive commands
 */
function createCommandValidationHook() {
  return async (input: any) => {
    if (input.tool_name === 'Bash') {
      const command = input.tool_input?.command || '';
      const trimmedCommand = command.trim();

      // Only allow 'mo' commands (Mole CLI)
      if (!trimmedCommand.startsWith('mo ')) {
        const error = new Error(
          `Security violation: Only 'mo' (Mole) commands are allowed. Attempted command: ${trimmedCommand}`
        );

        // Log the attempted violation
        await logAuditEvent({
          type: 'command_rejected',
          command: trimmedCommand,
          reason: 'Not a Mole command',
          timestamp: new Date().toISOString(),
        });

        throw error;
      }

      // Reject shell operators that could chain commands or redirect output
      // This prevents bypassing the whitelist via: mo status; rm -rf ~
      const dangerousPatterns = [
        /[;&|`$(){}[\]<>]/,  // Shell operators and command substitution
        /\n/,                 // Newlines (command chaining)
        /\\\s*\n/,            // Line continuation
      ];

      for (const pattern of dangerousPatterns) {
        if (pattern.test(trimmedCommand)) {
          const error = new Error(
            `Security violation: Shell operators not allowed in commands. Attempted command: ${trimmedCommand}`
          );

          // Log the attempted violation
          await logAuditEvent({
            type: 'command_rejected',
            command: trimmedCommand,
            reason: 'Contains shell operators',
            timestamp: new Date().toISOString(),
          });

          throw error;
        }
      }

      // Verify the command is strictly 'mo' followed by allowed arguments
      // Format: mo <subcommand> [--flags] [args]
      // Supports quoted arguments like: mo uninstall "Google Chrome"
      const moCommandPattern = /^mo\s+[a-z-]+(\s+(--?[a-z-]+|"[^"]+"|'[^']+'|\S+))*$/i;
      if (!moCommandPattern.test(trimmedCommand)) {
        const error = new Error(
          `Security violation: Invalid mo command format. Attempted command: ${trimmedCommand}`
        );

        // Log the attempted violation
        await logAuditEvent({
          type: 'command_rejected',
          command: trimmedCommand,
          reason: 'Invalid command format',
          timestamp: new Date().toISOString(),
        });

        throw error;
      }

      // Evaluate safety policy
      const decision = evaluatePolicy(trimmedCommand);

      // If command is not allowed, throw confirmation-required error
      if (!decision.allowed) {
        // Log the policy rejection
        await logAuditEvent({
          type: 'command_rejected',
          command: trimmedCommand,
          reason: decision.reason || 'Policy violation',
          timestamp: new Date().toISOString(),
        });

        // Throw confirmation-required error for the UI to handle
        throw new ConfirmationRequiredError(trimmedCommand, decision);
      }

      // Log approved command
      await logAuditEvent({
        type: 'command_approved',
        command: trimmedCommand,
        timestamp: new Date().toISOString(),
      });
    }

    return {};
  };
}

/**
 * Post-tool-use hook to log command execution results
 */
function createCommandLoggingHook() {
  return async (input: any) => {
    if (input.tool_name === 'Bash') {
      const command = input.tool_input?.command || '';
      const output = input.tool_output || {};

      await logAuditEvent({
        type: 'command_executed',
        command: command.trim(),
        exitCode: output.code,
        timestamp: new Date().toISOString(),
      });
    }

    return {};
  };
}

// ============================================================================
// Audit Logging
// ============================================================================

interface AuditEvent {
  type: 'command_approved' | 'command_rejected' | 'command_executed';
  command: string;
  reason?: string;
  exitCode?: number;
  timestamp: string;
}

/**
 * Log an audit event via Tauri backend
 */
async function logAuditEvent(event: AuditEvent): Promise<void> {
  try {
    await invoke('log_audit_event', { event });
  } catch (error) {
    // Don't throw - logging failures shouldn't break the agent
    console.error('Failed to log audit event:', error);
  }
}

// ============================================================================
// Agent Query
// ============================================================================

/**
 * Query the Claude agent with a user prompt
 * Returns an async iterator of stream messages
 */
export async function* queryAgent(options: AgentQueryOptions): AsyncGenerator<StreamMessage> {
  const { prompt, sessionId, timeout = DEFAULT_TIMEOUT_MS, onMessage, onError, onTimeout } = options;

  let timeoutId: NodeJS.Timeout | null = null;
  let timedOut = false;

  try {
    // Set up timeout that will fire if the entire query takes too long
    const timeoutPromise = new Promise<never>((_, reject) => {
      timeoutId = setTimeout(() => {
        timedOut = true;
        const timeoutError = new Error(`Agent query timed out after ${timeout}ms`);
        timeoutError.name = 'AgentTimeoutError';
        reject(timeoutError);
      }, timeout);
    });

    // Get workspace path
    const workspace = await getWorkspacePath();

    // Build agent options
    const agentOptions: AgentOptions = {
      cwd: workspace,
      model: currentConfig.model || DEFAULT_MODEL,
      settingSources: ['project'], // Auto-loads .claude/skills/mole.md from workspace
      systemPrompt: currentConfig.systemPrompt || DEFAULT_SYSTEM_PROMPT,
      resume: sessionId, // For multi-turn conversations

      // SECURITY: Only allow Bash tool (restricted to 'mo' commands via hook)
      allowedTools: ['Bash'],

      // API configuration
      ...(currentConfig.apiKey && { apiKey: currentConfig.apiKey }),
      ...(currentConfig.llmProxyUrl && {
        baseURL: currentConfig.llmProxyUrl,
      }),

      // Hooks for command validation and logging
      hooks: {
        PreToolUse: [
          {
            hooks: [createCommandValidationHook()],
          },
        ],
        PostToolUse: [
          {
            hooks: [createCommandLoggingHook()],
          },
        ],
      },
    };

    // Execute query
    const response = query({
      prompt,
      options: agentOptions,
    });

    // Race the response stream against the timeout
    // We need to race the entire stream, not just individual messages,
    // to ensure timeout fires even if no messages arrive
    const streamWithTimeout = async function* () {
      const iterator = response[Symbol.asyncIterator]();

      while (true) {
        // Race the next message against the timeout
        const result = await Promise.race([
          iterator.next(),
          timeoutPromise,
        ]);

        if (result.done) {
          break;
        }

        const message = result.value;

        // Call optional message handler
        if (onMessage) {
          try {
            onMessage(message);
          } catch (err) {
            console.error('Error in message handler:', err);
          }
        }

        yield message;
      }
    };

    // Stream messages with timeout enforcement
    try {
      for await (const message of streamWithTimeout()) {
        yield message;
      }
    } finally {
      // Clean up timeout
      if (timeoutId) {
        clearTimeout(timeoutId);
      }
    }
  } catch (error) {
    // Clean up timeout on error
    if (timeoutId) {
      clearTimeout(timeoutId);
    }

    const err = error instanceof Error ? error : new Error(String(error));

    // Check if this is a timeout error
    if (err.name === 'AgentTimeoutError' || err.message.includes('timed out')) {
      if (onTimeout) {
        try {
          onTimeout();
        } catch (handlerError) {
          console.error('Error in timeout handler:', handlerError);
        }
      }
    }

    // Call optional error handler
    if (onError) {
      try {
        onError(err);
      } catch (handlerError) {
        console.error('Error in error handler:', handlerError);
      }
    }

    throw err;
  }
}

// ============================================================================
// Convenience Functions
// ============================================================================

/**
 * Query the agent and collect all text responses into a single string
 */
export async function queryAgentText(options: AgentQueryOptions): Promise<string> {
  const textChunks: string[] = [];

  for await (const message of queryAgent(options)) {
    if (message.type === 'text') {
      textChunks.push(message.text);
    }
  }

  return textChunks.join('');
}

/**
 * Query the agent and collect all messages into an array
 */
export async function queryAgentMessages(options: AgentQueryOptions): Promise<StreamMessage[]> {
  const messages: StreamMessage[] = [];

  for await (const message of queryAgent(options)) {
    messages.push(message);
  }

  return messages;
}

// ============================================================================
// Exports
// ============================================================================

export default {
  configure: configureAgent,
  getConfig: getAgentConfig,
  query: queryAgent,
  queryText: queryAgentText,
  queryMessages: queryAgentMessages,
};
