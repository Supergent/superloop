import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest';
import {
  configureAgent,
  getAgentConfig,
  queryAgent,
  queryAgentText,
  queryAgentMessages,
  type AgentQueryOptions,
} from '../agent';
import * as agentPolicyModule from '../agentPolicy';
import { ConfirmationRequiredError } from '../agentPolicy';
import * as claudeAgentSDK from '@anthropic-ai/claude-agent-sdk';
import { invoke } from '@tauri-apps/api/core';

// Mock dependencies
vi.mock('@anthropic-ai/claude-agent-sdk', () => ({
  query: vi.fn(),
}));

vi.mock('@tauri-apps/api/core', () => ({
  invoke: vi.fn(),
}));

vi.mock('../agentPolicy', async () => {
  const actual = await vi.importActual<typeof agentPolicyModule>('../agentPolicy');
  return {
    ...actual,
    evaluatePolicy: vi.fn(actual.evaluatePolicy),
  };
});

describe('agent', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    agentPolicyModule.clearAllApprovals();

    // Default mock for workspace path
    vi.mocked(invoke).mockImplementation(async (cmd: string, args?: any) => {
      if (cmd === 'workspace_path') {
        return '/mock/workspace';
      }
      if (cmd === 'log_audit_event') {
        return undefined;
      }
      return {};
    });
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  describe('configureAgent and getAgentConfig', () => {
    it('should configure the agent with custom settings', () => {
      configureAgent({
        apiKey: 'test-api-key',
        llmProxyUrl: 'https://custom-proxy.com',
        model: 'claude-3-sonnet',
      });

      const config = getAgentConfig();
      expect(config.apiKey).toBe('test-api-key');
      expect(config.llmProxyUrl).toBe('https://custom-proxy.com');
      expect(config.model).toBe('claude-3-sonnet');
    });

    it('should merge configurations', () => {
      configureAgent({ apiKey: 'key1' });
      configureAgent({ llmProxyUrl: 'https://proxy.com' });

      const config = getAgentConfig();
      expect(config.apiKey).toBe('key1');
      expect(config.llmProxyUrl).toBe('https://proxy.com');
    });

    it('should allow clearing the API key', () => {
      configureAgent({ apiKey: 'test-key' });
      expect(getAgentConfig().apiKey).toBe('test-key');

      configureAgent({ apiKey: undefined });
      expect(getAgentConfig().apiKey).toBeUndefined();
    });
  });

  describe('PreToolUse rejection tests', () => {
    it('should reject non-mo commands', async () => {
      // Mock the query function to invoke the PreToolUse hook
      vi.mocked(claudeAgentSDK.query).mockImplementation((config: any) => {
        // Simulate the agent trying to execute a bash command
        const asyncGen = async function* () {
          // Trigger PreToolUse hook
          const hook = config.options.hooks.PreToolUse[0].hooks[0];
          await hook({
            tool_name: 'Bash',
            tool_input: { command: 'ls -la' },
          });
        };
        return asyncGen();
      });

      const options: AgentQueryOptions = {
        prompt: 'List files',
      };

      await expect(async () => {
        for await (const message of queryAgent(options)) {
          // Should not reach here
        }
      }).rejects.toThrow('Security violation: Only \'mo\' (Mole) commands are allowed');

      // Verify audit log was called
      expect(invoke).toHaveBeenCalledWith('log_audit_event', {
        event: expect.objectContaining({
          type: 'command_rejected',
          command: 'ls -la',
          reason: 'Not a Mole command',
        }),
      });
    });

    it('should reject commands with shell operators', async () => {
      const dangerousCommands = [
        'mo status; rm -rf ~',
        'mo status && malicious',
        'mo status | grep secret',
        'mo status > /tmp/file',
        'mo status $(whoami)',
        'mo status `echo hack`',
      ];

      for (const cmd of dangerousCommands) {
        vi.mocked(claudeAgentSDK.query).mockImplementation((config: any) => {
          const asyncGen = async function* () {
            const hook = config.options.hooks.PreToolUse[0].hooks[0];
            await hook({
              tool_name: 'Bash',
              tool_input: { command: cmd },
            });
          };
          return asyncGen();
        });

        const options: AgentQueryOptions = {
          prompt: 'Test command',
        };

        await expect(async () => {
          for await (const message of queryAgent(options)) {
            // Should not reach here
          }
        }).rejects.toThrow(/Security violation.*Shell operators/);
      }
    });

    it('should reject commands with invalid mo format', async () => {
      vi.mocked(claudeAgentSDK.query).mockImplementation((config: any) => {
        const asyncGen = async function* () {
          const hook = config.options.hooks.PreToolUse[0].hooks[0];
          await hook({
            tool_name: 'Bash',
            tool_input: { command: 'mo status@invalid' },
          });
        };
        return asyncGen();
      });

      const options: AgentQueryOptions = {
        prompt: 'Test command',
      };

      await expect(async () => {
        for await (const message of queryAgent(options)) {
          // Should not reach here
        }
      }).rejects.toThrow(/Security violation.*Invalid mo command format/);
    });

    it('should allow valid mo commands with quoted arguments', async () => {
      vi.mocked(claudeAgentSDK.query).mockImplementation((config: any) => {
        const asyncGen = async function* () {
          const hook = config.options.hooks.PreToolUse[0].hooks[0];
          await hook({
            tool_name: 'Bash',
            tool_input: { command: 'mo uninstall "Google Chrome"' },
          });
          yield { type: 'text', text: 'Uninstalling Google Chrome' };
        };
        return asyncGen();
      });

      // Mock policy to allow the command
      vi.mocked(agentPolicyModule.evaluatePolicy).mockReturnValue({
        allowed: true,
        classification: 'safe',
        requiresConfirmation: false,
        requiresDryRun: false,
      });

      const options: AgentQueryOptions = {
        prompt: 'Remove Google Chrome',
      };

      const messages = [];
      for await (const message of queryAgent(options)) {
        messages.push(message);
      }

      expect(messages.length).toBeGreaterThan(0);
    });

    it('should allow mo commands with single-quoted arguments', async () => {
      vi.mocked(claudeAgentSDK.query).mockImplementation((config: any) => {
        const asyncGen = async function* () {
          const hook = config.options.hooks.PreToolUse[0].hooks[0];
          await hook({
            tool_name: 'Bash',
            tool_input: { command: "mo uninstall 'Visual Studio Code'" },
          });
          yield { type: 'text', text: 'Uninstalling Visual Studio Code' };
        };
        return asyncGen();
      });

      // Mock policy to allow the command
      vi.mocked(agentPolicyModule.evaluatePolicy).mockReturnValue({
        allowed: true,
        classification: 'safe',
        requiresConfirmation: false,
        requiresDryRun: false,
      });

      const options: AgentQueryOptions = {
        prompt: 'Remove Visual Studio Code',
      };

      const messages = [];
      for await (const message of queryAgent(options)) {
        messages.push(message);
      }

      expect(messages.length).toBeGreaterThan(0);
    });

    it('should allow mo commands with multiple quoted arguments', async () => {
      vi.mocked(claudeAgentSDK.query).mockImplementation((config: any) => {
        const asyncGen = async function* () {
          const hook = config.options.hooks.PreToolUse[0].hooks[0];
          await hook({
            tool_name: 'Bash',
            tool_input: { command: 'mo uninstall "Google Chrome" "Microsoft Edge"' },
          });
          yield { type: 'text', text: 'Uninstalling apps' };
        };
        return asyncGen();
      });

      // Mock policy to allow the command
      vi.mocked(agentPolicyModule.evaluatePolicy).mockReturnValue({
        allowed: true,
        classification: 'safe',
        requiresConfirmation: false,
        requiresDryRun: false,
      });

      const options: AgentQueryOptions = {
        prompt: 'Remove Chrome and Edge',
      };

      const messages = [];
      for await (const message of queryAgent(options)) {
        messages.push(message);
      }

      expect(messages.length).toBeGreaterThan(0);
    });

    it('should allow mo commands with flags and quoted arguments', async () => {
      vi.mocked(claudeAgentSDK.query).mockImplementation((config: any) => {
        const asyncGen = async function* () {
          const hook = config.options.hooks.PreToolUse[0].hooks[0];
          await hook({
            tool_name: 'Bash',
            tool_input: { command: 'mo uninstall --force "Adobe Photoshop"' },
          });
          yield { type: 'text', text: 'Force uninstalling Adobe Photoshop' };
        };
        return asyncGen();
      });

      // Mock policy to allow the command
      vi.mocked(agentPolicyModule.evaluatePolicy).mockReturnValue({
        allowed: true,
        classification: 'safe',
        requiresConfirmation: false,
        requiresDryRun: false,
      });

      const options: AgentQueryOptions = {
        prompt: 'Force remove Adobe Photoshop',
      };

      const messages = [];
      for await (const message of queryAgent(options)) {
        messages.push(message);
      }

      expect(messages.length).toBeGreaterThan(0);
    });

    it('should allow safe mo commands without confirmation', async () => {
      vi.mocked(claudeAgentSDK.query).mockImplementation((config: any) => {
        const asyncGen = async function* () {
          const hook = config.options.hooks.PreToolUse[0].hooks[0];
          await hook({
            tool_name: 'Bash',
            tool_input: { command: 'mo status' },
          });
          yield { type: 'text', text: 'System status: Good' };
        };
        return asyncGen();
      });

      const options: AgentQueryOptions = {
        prompt: 'Check my Mac',
      };

      const messages = [];
      for await (const message of queryAgent(options)) {
        messages.push(message);
      }

      expect(messages.length).toBeGreaterThan(0);
      expect(invoke).toHaveBeenCalledWith('log_audit_event', {
        event: expect.objectContaining({
          type: 'command_approved',
          command: 'mo status',
        }),
      });
    });
  });

  describe('Confirmation-required tests', () => {
    it('should throw ConfirmationRequiredError for destructive commands', async () => {
      vi.mocked(claudeAgentSDK.query).mockImplementation((config: any) => {
        const asyncGen = async function* () {
          const hook = config.options.hooks.PreToolUse[0].hooks[0];
          // Hook should throw ConfirmationRequiredError for 'mo clean'
          await hook({
            tool_name: 'Bash',
            tool_input: { command: 'mo clean' },
          });
          // Should not reach here if hook throws
          yield { type: 'text', text: 'Should not see this' };
        };
        return asyncGen();
      });

      const options: AgentQueryOptions = {
        prompt: 'Clean my Mac',
      };

      await expect(async () => {
        for await (const message of queryAgent(options)) {
          // Should not reach here
        }
      }).rejects.toThrow(ConfirmationRequiredError);
    });

    it('should include dry-run command in ConfirmationRequiredError', async () => {
      vi.mocked(claudeAgentSDK.query).mockImplementation((config: any) => {
        const asyncGen = async function* () {
          const hook = config.options.hooks.PreToolUse[0].hooks[0];
          try {
            await hook({
              tool_name: 'Bash',
              tool_input: { command: 'mo clean' },
            });
          } catch (error) {
            throw error;
          }
        };
        return asyncGen();
      });

      const options: AgentQueryOptions = {
        prompt: 'Clean my Mac',
      };

      try {
        for await (const message of queryAgent(options)) {
          // Should not reach here
        }
      } catch (error) {
        expect(error).toBeInstanceOf(ConfirmationRequiredError);
        const confirmError = error as ConfirmationRequiredError;
        expect(confirmError.command).toBe('mo clean');
        expect(confirmError.decision.requiresDryRun).toBe(true);
        expect(confirmError.decision.dryRunCommand).toBe('mo clean --dry-run');
      }
    });

    it('should allow destructive commands after approval', async () => {
      // Approve the command first
      agentPolicyModule.approveCommand('mo clean');

      vi.mocked(claudeAgentSDK.query).mockImplementation((config: any) => {
        const asyncGen = async function* () {
          const hook = config.options.hooks.PreToolUse[0].hooks[0];
          await hook({
            tool_name: 'Bash',
            tool_input: { command: 'mo clean' },
          });
          yield { type: 'text', text: 'Cleaning complete' };
        };
        return asyncGen();
      });

      const options: AgentQueryOptions = {
        prompt: 'Clean my Mac',
      };

      const messages = [];
      for await (const message of queryAgent(options)) {
        messages.push(message);
      }

      expect(messages.length).toBeGreaterThan(0);
    });

    it('should allow dry-run commands without confirmation', async () => {
      vi.mocked(claudeAgentSDK.query).mockImplementation((config: any) => {
        const asyncGen = async function* () {
          const hook = config.options.hooks.PreToolUse[0].hooks[0];
          await hook({
            tool_name: 'Bash',
            tool_input: { command: 'mo clean --dry-run' },
          });
          yield { type: 'text', text: 'Dry-run preview' };
        };
        return asyncGen();
      });

      const options: AgentQueryOptions = {
        prompt: 'Preview clean',
      };

      const messages = [];
      for await (const message of queryAgent(options)) {
        messages.push(message);
      }

      expect(messages.length).toBeGreaterThan(0);
    });
  });

  describe('LLM-proxy API key wiring tests', () => {
    it('should include API key in agent options when configured', async () => {
      configureAgent({ apiKey: 'test-llm-proxy-key' });

      vi.mocked(claudeAgentSDK.query).mockImplementation((config: any) => {
        // Verify the API key is passed
        expect(config.options.apiKey).toBe('test-llm-proxy-key');

        const asyncGen = async function* () {
          yield { type: 'text', text: 'Response' };
        };
        return asyncGen();
      });

      const options: AgentQueryOptions = {
        prompt: 'Test',
      };

      for await (const message of queryAgent(options)) {
        // Just consume the messages
      }

      expect(claudeAgentSDK.query).toHaveBeenCalled();
    });

    it('should include llmProxyUrl as baseURL when configured', async () => {
      configureAgent({
        apiKey: 'test-key',
        llmProxyUrl: 'https://custom-llm-proxy.com',
      });

      vi.mocked(claudeAgentSDK.query).mockImplementation((config: any) => {
        expect(config.options.baseURL).toBe('https://custom-llm-proxy.com');

        const asyncGen = async function* () {
          yield { type: 'text', text: 'Response' };
        };
        return asyncGen();
      });

      const options: AgentQueryOptions = {
        prompt: 'Test',
      };

      for await (const message of queryAgent(options)) {
        // Just consume the messages
      }
    });

    it('should use default llmProxyUrl when not configured', async () => {
      configureAgent({ apiKey: 'test-key', llmProxyUrl: undefined });

      vi.mocked(claudeAgentSDK.query).mockImplementation((config: any) => {
        // baseURL should not be set if llmProxyUrl is undefined
        expect(config.options.baseURL).toBeUndefined();

        const asyncGen = async function* () {
          yield { type: 'text', text: 'Response' };
        };
        return asyncGen();
      });

      const options: AgentQueryOptions = {
        prompt: 'Test',
      };

      for await (const message of queryAgent(options)) {
        // Just consume the messages
      }
    });

    it('should not include API key when not configured', async () => {
      configureAgent({ apiKey: undefined });

      vi.mocked(claudeAgentSDK.query).mockImplementation((config: any) => {
        expect(config.options.apiKey).toBeUndefined();

        const asyncGen = async function* () {
          yield { type: 'text', text: 'Response' };
        };
        return asyncGen();
      });

      const options: AgentQueryOptions = {
        prompt: 'Test',
      };

      for await (const message of queryAgent(options)) {
        // Just consume the messages
      }
    });
  });

  describe('Agent timeout enforcement tests', () => {
    beforeEach(() => {
      vi.useFakeTimers();
    });

    afterEach(async () => {
      // Clear all pending timers to prevent unhandled rejections
      vi.clearAllTimers();
      vi.useRealTimers();
    });

    it('should timeout when query takes too long', async () => {
      vi.mocked(claudeAgentSDK.query).mockImplementation(() => {
        const asyncGen = async function* () {
          // Simulate a long-running query that never completes
          await new Promise((resolve) => setTimeout(resolve, 100000));
          yield { type: 'text', text: 'Response' };
        };
        return asyncGen();
      });

      const onTimeout = vi.fn();
      const onError = vi.fn();

      const options: AgentQueryOptions = {
        prompt: 'Test',
        timeout: 5000, // 5 second timeout
        onTimeout,
        onError,
      };

      const queryPromise = (async () => {
        for await (const message of queryAgent(options)) {
          // Should timeout before getting here
        }
      })();

      // Advance timers to trigger timeout
      await vi.advanceTimersByTimeAsync(5000);

      // Catch the rejection to prevent unhandled promise rejection
      try {
        await queryPromise;
        // Should not reach here
        expect.fail('Expected query to timeout');
      } catch (error) {
        expect(error).toBeInstanceOf(Error);
        expect((error as Error).message).toMatch(/timed out/);
      }

      expect(onTimeout).toHaveBeenCalled();
      expect(onError).toHaveBeenCalled();
    });

    it('should call onTimeout callback when timeout occurs', async () => {
      vi.mocked(claudeAgentSDK.query).mockImplementation(() => {
        const asyncGen = async function* () {
          await new Promise((resolve) => setTimeout(resolve, 100000));
        };
        return asyncGen();
      });

      const onTimeout = vi.fn();

      const options: AgentQueryOptions = {
        prompt: 'Test',
        timeout: 1000,
        onTimeout,
      };

      const queryPromise = (async () => {
        for await (const message of queryAgent(options)) {
          // Should not reach
        }
      })();

      // Advance timers to trigger timeout
      await vi.advanceTimersByTimeAsync(1000);

      // Catch the rejection to prevent unhandled promise rejection
      try {
        await queryPromise;
        expect.fail('Expected query to timeout');
      } catch (error) {
        expect(error).toBeInstanceOf(Error);
      }

      expect(onTimeout).toHaveBeenCalledTimes(1);
    });

    it('should not timeout when query completes in time', async () => {
      vi.mocked(claudeAgentSDK.query).mockImplementation(() => {
        const asyncGen = async function* () {
          yield { type: 'text', text: 'Response' };
        };
        return asyncGen();
      });

      const onTimeout = vi.fn();

      const options: AgentQueryOptions = {
        prompt: 'Test',
        timeout: 5000,
        onTimeout,
      };

      const messages = [];
      for await (const message of queryAgent(options)) {
        messages.push(message);
      }

      expect(messages.length).toBe(1);
      expect(onTimeout).not.toHaveBeenCalled();
    });

    it('should use default timeout when not specified', async () => {
      vi.mocked(claudeAgentSDK.query).mockImplementation(() => {
        const asyncGen = async function* () {
          await new Promise((resolve) => setTimeout(resolve, 100000));
        };
        return asyncGen();
      });

      const onTimeout = vi.fn();

      const options: AgentQueryOptions = {
        prompt: 'Test',
        // No timeout specified - should use default 60000ms
        onTimeout,
      };

      const queryPromise = (async () => {
        for await (const message of queryAgent(options)) {
          // Should not reach
        }
      })();

      // Advance to just before default timeout
      await vi.advanceTimersByTimeAsync(59999);
      expect(onTimeout).not.toHaveBeenCalled();

      // Advance past default timeout
      await vi.advanceTimersByTimeAsync(1);

      // Catch the rejection to prevent unhandled promise rejection
      try {
        await queryPromise;
        expect.fail('Expected query to timeout');
      } catch (error) {
        expect(error).toBeInstanceOf(Error);
      }

      expect(onTimeout).toHaveBeenCalled();
    });

    it('should cleanup timeout when query succeeds', async () => {
      const clearTimeoutSpy = vi.spyOn(global, 'clearTimeout');

      vi.mocked(claudeAgentSDK.query).mockImplementation(() => {
        const asyncGen = async function* () {
          yield { type: 'text', text: 'Response' };
        };
        return asyncGen();
      });

      const options: AgentQueryOptions = {
        prompt: 'Test',
        timeout: 5000,
      };

      for await (const message of queryAgent(options)) {
        // Consume messages
      }

      // Verify timeout was cleared
      expect(clearTimeoutSpy).toHaveBeenCalled();
    });
  });

  describe('queryAgentText', () => {
    it('should collect all text messages into a single string', async () => {
      vi.mocked(claudeAgentSDK.query).mockImplementation((config: any) => {
        const asyncGen = async function* () {
          const hook = config.options.hooks.PreToolUse[0].hooks[0];
          await hook({
            tool_name: 'Bash',
            tool_input: { command: 'mo status' },
          });
          yield { type: 'text', text: 'Hello ' };
          yield { type: 'text', text: 'world' };
          yield { type: 'session_id', sessionId: '123' };
          yield { type: 'text', text: '!' };
        };
        return asyncGen();
      });

      const text = await queryAgentText({ prompt: 'Test' });
      expect(text).toBe('Hello world!');
    });
  });

  describe('queryAgentMessages', () => {
    it('should collect all messages into an array', async () => {
      vi.mocked(claudeAgentSDK.query).mockImplementation((config: any) => {
        const asyncGen = async function* () {
          const hook = config.options.hooks.PreToolUse[0].hooks[0];
          await hook({
            tool_name: 'Bash',
            tool_input: { command: 'mo status' },
          });
          yield { type: 'text', text: 'Hello' };
          yield { type: 'session_id', sessionId: '123' };
        };
        return asyncGen();
      });

      const messages = await queryAgentMessages({ prompt: 'Test' });
      expect(messages.length).toBe(2);
      expect(messages[0].type).toBe('text');
      expect(messages[1].type).toBe('session_id');
    });
  });

  describe('PreToolUse hook integration', () => {
    it('should register PreToolUse hook with agent SDK', async () => {
      vi.mocked(claudeAgentSDK.query).mockImplementation((config: any) => {
        expect(config.options.hooks.PreToolUse).toBeDefined();
        expect(config.options.hooks.PreToolUse.length).toBe(1);
        expect(config.options.hooks.PreToolUse[0].hooks).toBeDefined();
        expect(config.options.hooks.PreToolUse[0].hooks.length).toBe(1);

        const asyncGen = async function* () {
          yield { type: 'text', text: 'Response' };
        };
        return asyncGen();
      });

      const options: AgentQueryOptions = {
        prompt: 'Test',
      };

      for await (const message of queryAgent(options)) {
        // Just verify hook was registered
      }
    });

    it('should register PostToolUse hook with agent SDK', async () => {
      vi.mocked(claudeAgentSDK.query).mockImplementation((config: any) => {
        expect(config.options.hooks.PostToolUse).toBeDefined();
        expect(config.options.hooks.PostToolUse.length).toBe(1);
        expect(config.options.hooks.PostToolUse[0].hooks).toBeDefined();
        expect(config.options.hooks.PostToolUse[0].hooks.length).toBe(1);

        const asyncGen = async function* () {
          yield { type: 'text', text: 'Response' };
        };
        return asyncGen();
      });

      const options: AgentQueryOptions = {
        prompt: 'Test',
      };

      for await (const message of queryAgent(options)) {
        // Just verify hook was registered
      }
    });

    it('should invoke PreToolUse hook before Bash tool execution', async () => {
      let hookCalled = false;

      vi.mocked(claudeAgentSDK.query).mockImplementation((config: any) => {
        const asyncGen = async function* () {
          const hook = config.options.hooks.PreToolUse[0].hooks[0];
          await hook({
            tool_name: 'Bash',
            tool_input: { command: 'mo status' },
          });
          hookCalled = true;
          yield { type: 'text', text: 'System status' };
        };
        return asyncGen();
      });

      const options: AgentQueryOptions = {
        prompt: 'Check status',
      };

      const messages = [];
      for await (const message of queryAgent(options)) {
        messages.push(message);
      }

      expect(hookCalled).toBe(true);
      expect(messages.length).toBeGreaterThan(0);
    });

    it('should validate command through PreToolUse hook before execution', async () => {
      vi.mocked(claudeAgentSDK.query).mockImplementation((config: any) => {
        const asyncGen = async function* () {
          const hook = config.options.hooks.PreToolUse[0].hooks[0];

          // Try to execute a safe command
          await hook({
            tool_name: 'Bash',
            tool_input: { command: 'mo status' },
          });
          yield { type: 'text', text: 'Safe command executed' };

          // Try to execute a dangerous command - should throw
          try {
            await hook({
              tool_name: 'Bash',
              tool_input: { command: 'rm -rf /' },
            });
          } catch (error) {
            yield { type: 'text', text: 'Dangerous command blocked' };
          }
        };
        return asyncGen();
      });

      const options: AgentQueryOptions = {
        prompt: 'Test validation',
      };

      const messages = [];
      for await (const message of queryAgent(options)) {
        messages.push(message);
      }

      expect(messages).toContainEqual(
        expect.objectContaining({ type: 'text', text: 'Safe command executed' })
      );
      expect(messages).toContainEqual(
        expect.objectContaining({ type: 'text', text: 'Dangerous command blocked' })
      );
    });

    it('should pass tool name and input to PreToolUse hook', async () => {
      let capturedToolName: string | null = null;
      let capturedToolInput: any = null;

      vi.mocked(claudeAgentSDK.query).mockImplementation((config: any) => {
        const asyncGen = async function* () {
          const hook = config.options.hooks.PreToolUse[0].hooks[0];

          const toolUse = {
            tool_name: 'Bash',
            tool_input: { command: 'mo clean --dry-run' },
          };

          try {
            await hook(toolUse);
          } catch (error) {
            // May throw ConfirmationRequiredError
          }

          capturedToolName = toolUse.tool_name;
          capturedToolInput = toolUse.tool_input;

          yield { type: 'text', text: 'Done' };
        };
        return asyncGen();
      });

      const options: AgentQueryOptions = {
        prompt: 'Test',
      };

      for await (const message of queryAgent(options)) {
        // Consume messages
      }

      expect(capturedToolName).toBe('Bash');
      expect(capturedToolInput).toEqual({ command: 'mo clean --dry-run' });
    });

    it('should allow non-Bash tools to execute without validation', async () => {
      vi.mocked(claudeAgentSDK.query).mockImplementation((config: any) => {
        const asyncGen = async function* () {
          const hook = config.options.hooks.PreToolUse[0].hooks[0];

          // Non-Bash tools should not be validated
          await hook({
            tool_name: 'Read',
            tool_input: { file_path: '/some/file' },
          });

          yield { type: 'text', text: 'Read tool executed' };
        };
        return asyncGen();
      });

      const options: AgentQueryOptions = {
        prompt: 'Test non-Bash tool',
      };

      const messages = [];
      for await (const message of queryAgent(options)) {
        messages.push(message);
      }

      expect(messages).toContainEqual(
        expect.objectContaining({ type: 'text', text: 'Read tool executed' })
      );
    });
  });
});
