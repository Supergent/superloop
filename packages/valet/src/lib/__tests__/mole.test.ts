import { describe, it, expect, vi, beforeEach } from 'vitest';
import { Command } from '@tauri-apps/plugin-shell';
import * as mole from '../mole';

// Mock the Tauri API
vi.mock('@tauri-apps/api/core', () => ({
  invoke: vi.fn(),
}));

vi.mock('@tauri-apps/plugin-shell', () => ({
  Command: {
    create: vi.fn(),
  },
}));

vi.mock('@tauri-apps/api/path', () => ({
  homeDir: vi.fn().mockResolvedValue('/Users/test'),
}));

describe('mole - Command Execution Paths', () => {
  beforeEach(async () => {
    vi.clearAllMocks();

    // Mock get_home_dir invoke call
    const { invoke } = await import('@tauri-apps/api/core');
    vi.mocked(invoke).mockImplementation(async (cmd: string) => {
      if (cmd === 'get_home_dir') {
        return '/Users/test';
      }
      if (cmd === 'ensure_mole_installed_command') {
        return '/Users/test/Library/Application Support/Valet/bin/mo';
      }
      return null;
    });
  });

  describe('executeMoleCommand', () => {
    it('should use the "mo" command name as defined in capabilities allowlist', async () => {
      // Setup mock command that will execute
      const mockExecute = vi.fn().mockResolvedValue({
        stdout: JSON.stringify({
          cpu: { usage: 25 },
          memory: { used: 8000000000, total: 16000000000 },
          disk: { available: 50000000000, total: 250000000000 },
          network: { download: 1000000, upload: 500000 },
        }),
        stderr: '',
        code: 0,
      });

      const mockCommand = {
        execute: mockExecute,
      };

      vi.mocked(Command.create).mockReturnValue(mockCommand as any);

      // Execute getSystemStatus which calls executeMoleCommand internally
      await mole.getSystemStatus();

      // Verify Command.create was called with 'mo' command name and env with PATH
      expect(Command.create).toHaveBeenCalledWith(
        'mo',
        ['status', '--json'],
        expect.objectContaining({
          env: expect.objectContaining({
            PATH: expect.stringContaining('/Users/test/Library/Application Support/Valet/bin'),
          }),
        })
      );
    });

    it('should pass args correctly when executing mo clean', async () => {
      const mockExecute = vi.fn().mockResolvedValue({
        stdout: 'Cleaned 1GB of cache files',
        stderr: '',
        code: 0,
      });

      const mockCommand = {
        execute: mockExecute,
      };

      vi.mocked(Command.create).mockReturnValue(mockCommand as any);

      await mole.cleanSystem({ dryRun: true });

      expect(Command.create).toHaveBeenCalledWith(
        'mo',
        ['clean', '--dry-run'],
        expect.objectContaining({
          env: expect.objectContaining({
            PATH: expect.stringContaining('/Users/test/Library/Application Support/Valet/bin'),
          }),
        })
      );
    });

    it('should pass args correctly when executing mo analyze', async () => {
      const mockExecute = vi.fn().mockResolvedValue({
        stdout: 'Analyzing disk usage...',
        stderr: '',
        code: 0,
      });

      const mockCommand = {
        execute: mockExecute,
      };

      vi.mocked(Command.create).mockReturnValue(mockCommand as any);

      await mole.analyzeDiskUsage('/Users/test/Documents');

      expect(Command.create).toHaveBeenCalledWith(
        'mo',
        ['analyze', '/Users/test/Documents'],
        expect.objectContaining({
          env: expect.objectContaining({
            PATH: expect.stringContaining('/Users/test/Library/Application Support/Valet/bin'),
          }),
        })
      );
    });

    it('should pass args correctly when executing mo uninstall', async () => {
      const mockExecute = vi.fn().mockResolvedValue({
        stdout: 'Uninstalled Slack.app',
        stderr: '',
        code: 0,
      });

      const mockCommand = {
        execute: mockExecute,
      };

      vi.mocked(Command.create).mockReturnValue(mockCommand as any);

      await mole.uninstallApp('Slack');

      expect(Command.create).toHaveBeenCalledWith(
        'mo',
        ['uninstall', 'Slack'],
        expect.objectContaining({
          env: expect.objectContaining({
            PATH: expect.stringContaining('/Users/test/Library/Application Support/Valet/bin'),
          }),
        })
      );
    });

    it('should pass args correctly when executing mo optimize', async () => {
      const mockExecute = vi.fn().mockResolvedValue({
        stdout: 'System optimized',
        stderr: '',
        code: 0,
      });

      const mockCommand = {
        execute: mockExecute,
      };

      vi.mocked(Command.create).mockReturnValue(mockCommand as any);

      await mole.optimizeSystem({ dryRun: false });

      expect(Command.create).toHaveBeenCalledWith(
        'mo',
        ['optimize'],
        expect.objectContaining({
          env: expect.objectContaining({
            PATH: expect.stringContaining('/Users/test/Library/Application Support/Valet/bin'),
          }),
        })
      );
    });

    it('should pass args correctly when executing mo purge', async () => {
      const mockExecute = vi.fn().mockResolvedValue({
        stdout: 'Purged developer artifacts',
        stderr: '',
        code: 0,
      });

      const mockCommand = {
        execute: mockExecute,
      };

      vi.mocked(Command.create).mockReturnValue(mockCommand as any);

      await mole.purgeDeveloperArtifacts({ dryRun: true });

      expect(Command.create).toHaveBeenCalledWith(
        'mo',
        ['purge', '--dry-run'],
        expect.objectContaining({
          env: expect.objectContaining({
            PATH: expect.stringContaining('/Users/test/Library/Application Support/Valet/bin'),
          }),
        })
      );
    });

    it('should pass args correctly when executing mo installer', async () => {
      const mockExecute = vi.fn().mockResolvedValue({
        stdout: 'Cleaned installer files',
        stderr: '',
        code: 0,
      });

      const mockCommand = {
        execute: mockExecute,
      };

      vi.mocked(Command.create).mockReturnValue(mockCommand as any);

      await mole.cleanupInstallers({ dryRun: false });

      expect(Command.create).toHaveBeenCalledWith(
        'mo',
        ['installer'],
        expect.objectContaining({
          env: expect.objectContaining({
            PATH: expect.stringContaining('/Users/test/Library/Application Support/Valet/bin'),
          }),
        })
      );
    });
  });

  describe('ensureMoleInstalled', () => {
    it('should invoke ensure_mole_installed_command and return path', async () => {
      const { invoke } = await import('@tauri-apps/api/core');
      const mockInvoke = vi.mocked(invoke);

      mockInvoke.mockResolvedValue('/Users/test/Library/Application Support/Valet/bin/mo');

      const result = await mole.ensureMoleInstalled();

      expect(mockInvoke).toHaveBeenCalledWith('ensure_mole_installed_command');
      expect(result).toBe('/Users/test/Library/Application Support/Valet/bin/mo');
    });
  });

  describe('command execution', () => {
    it('should execute commands using the "mo" command name', async () => {
      const mockExecute = vi.fn().mockResolvedValue({
        stdout: JSON.stringify({
          cpu: { usage: 25 },
          memory: { used: 8000000000, total: 16000000000 },
          disk: { available: 50000000000, total: 250000000000 },
          network: { download: 1000000, upload: 500000 },
        }),
        stderr: '',
        code: 0,
      });

      const mockCommand = {
        execute: mockExecute,
      };

      vi.mocked(Command.create).mockReturnValue(mockCommand as any);

      await mole.getSystemStatus();

      // Verify that Command.create is called with 'mo' command name (not 'exec') and env with PATH
      expect(Command.create).toHaveBeenCalledWith(
        'mo',
        ['status', '--json'],
        expect.objectContaining({
          env: expect.objectContaining({
            PATH: expect.stringContaining('/Users/test/Library/Application Support/Valet/bin'),
          }),
        })
      );
    });
  });
});
