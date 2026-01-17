import { describe, it, expect, beforeEach, vi } from 'vitest';
import {
  classifyCommand,
  evaluatePolicy,
  approveCommand,
  isCommandApproved,
  revokeApproval,
  clearAllApprovals,
  getActiveApprovals,
  supportsDryRun,
  toDryRunCommand,
  isDryRun,
  ConfirmationRequiredError,
} from '../agentPolicy';

describe('agentPolicy', () => {
  beforeEach(() => {
    clearAllApprovals();
    vi.clearAllMocks();
  });

  describe('classifyCommand', () => {
    it('should classify safe commands', () => {
      expect(classifyCommand('mo status')).toBe('safe');
      expect(classifyCommand('mo analyze')).toBe('safe');
      expect(classifyCommand('MO STATUS')).toBe('safe'); // Case-insensitive
      expect(classifyCommand('  mo status  ')).toBe('safe'); // Handles whitespace
    });

    it('should classify destructive commands', () => {
      expect(classifyCommand('mo clean')).toBe('destructive');
      expect(classifyCommand('mo uninstall')).toBe('destructive');
      expect(classifyCommand('mo optimize')).toBe('destructive');
      expect(classifyCommand('mo purge')).toBe('destructive');
    });

    it('should classify dry-run commands as safe', () => {
      expect(classifyCommand('mo clean --dry-run')).toBe('safe');
      expect(classifyCommand('mo optimize --dry-run')).toBe('safe');
      expect(classifyCommand('mo clean -n')).toBe('safe');
    });

    it('should classify unknown commands as requires-confirmation', () => {
      expect(classifyCommand('mo foobar')).toBe('requires-confirmation');
      expect(classifyCommand('unknown command')).toBe('requires-confirmation');
    });
  });

  describe('supportsDryRun', () => {
    it('should return true for commands that support dry-run', () => {
      expect(supportsDryRun('mo clean')).toBe(true);
      expect(supportsDryRun('mo optimize')).toBe(true);
      expect(supportsDryRun('mo purge')).toBe(true);
      expect(supportsDryRun('mo installer')).toBe(true);
    });

    it('should return false for commands that do not support dry-run', () => {
      expect(supportsDryRun('mo status')).toBe(false);
      expect(supportsDryRun('mo analyze')).toBe(false);
      expect(supportsDryRun('mo uninstall')).toBe(false);
    });
  });

  describe('toDryRunCommand', () => {
    it('should add --dry-run flag to commands', () => {
      expect(toDryRunCommand('mo clean')).toBe('mo clean --dry-run');
      expect(toDryRunCommand('mo optimize')).toBe('mo optimize --dry-run');
    });

    it('should not add --dry-run if it already exists', () => {
      expect(toDryRunCommand('mo clean --dry-run')).toBe('mo clean --dry-run');
      expect(toDryRunCommand('mo clean -n')).toBe('mo clean -n');
    });

    it('should insert --dry-run after subcommand', () => {
      expect(toDryRunCommand('mo clean /path')).toBe('mo clean --dry-run /path');
      expect(toDryRunCommand('mo optimize --verbose')).toBe('mo optimize --dry-run --verbose');
    });
  });

  describe('isDryRun', () => {
    it('should detect dry-run flag', () => {
      expect(isDryRun('mo clean --dry-run')).toBe(true);
      expect(isDryRun('mo clean -n')).toBe(true);
      expect(isDryRun('mo clean')).toBe(false);
    });
  });

  describe('approveCommand and isCommandApproved', () => {
    it('should approve and check command approval', () => {
      const command = 'mo clean';

      expect(isCommandApproved(command)).toBe(false);

      approveCommand(command);

      expect(isCommandApproved(command)).toBe(true);
    });

    it('should normalize commands for approval checking', () => {
      approveCommand('mo clean');

      expect(isCommandApproved('MO CLEAN')).toBe(true);
      expect(isCommandApproved('  mo  clean  ')).toBe(true);
    });

    it('should handle approval expiration', () => {
      vi.useFakeTimers();

      const command = 'mo clean';
      approveCommand(command, 1000); // 1 second expiration

      expect(isCommandApproved(command)).toBe(true);

      // Fast-forward past expiration
      vi.advanceTimersByTime(1001);

      expect(isCommandApproved(command)).toBe(false);

      vi.useRealTimers();
    });
  });

  describe('revokeApproval', () => {
    it('should revoke approval for a command', () => {
      const command = 'mo clean';

      approveCommand(command);
      expect(isCommandApproved(command)).toBe(true);

      revokeApproval(command);
      expect(isCommandApproved(command)).toBe(false);
    });
  });

  describe('getActiveApprovals', () => {
    it('should return active approvals', () => {
      approveCommand('mo clean');
      approveCommand('mo optimize');

      const active = getActiveApprovals();
      expect(active.length).toBe(2);
      expect(active.map(a => a.command)).toContain('mo clean');
      expect(active.map(a => a.command)).toContain('mo optimize');
    });

    it('should filter out expired approvals', () => {
      vi.useFakeTimers();

      approveCommand('mo clean', 1000); // Expires in 1 second
      approveCommand('mo optimize', 10000); // Expires in 10 seconds

      // Fast-forward past first expiration
      vi.advanceTimersByTime(1001);

      const active = getActiveApprovals();
      expect(active.length).toBe(1);
      expect(active[0].command).toBe('mo optimize');

      vi.useRealTimers();
    });

    it('should include expiration timestamps for all approvals', () => {
      vi.useFakeTimers();
      const now = Date.now();

      approveCommand('mo clean', 5000);
      approveCommand('mo optimize', 10000);

      const active = getActiveApprovals();
      expect(active.length).toBe(2);

      const cleanApproval = active.find(a => a.command === 'mo clean');
      const optimizeApproval = active.find(a => a.command === 'mo optimize');

      expect(cleanApproval?.expiresAt).toBe(now + 5000);
      expect(optimizeApproval?.expiresAt).toBe(now + 10000);

      vi.useRealTimers();
    });

    it('should filter all expired approvals when multiple expire', () => {
      vi.useFakeTimers();

      approveCommand('mo clean', 1000);
      approveCommand('mo optimize', 1500);
      approveCommand('mo purge', 10000);

      // Fast-forward past first two expirations
      vi.advanceTimersByTime(2000);

      const active = getActiveApprovals();
      expect(active.length).toBe(1);
      expect(active[0].command).toBe('mo purge');

      vi.useRealTimers();
    });

    it('should return empty array when all approvals expire', () => {
      vi.useFakeTimers();

      approveCommand('mo clean', 1000);
      approveCommand('mo optimize', 1500);

      // Fast-forward past all expirations
      vi.advanceTimersByTime(2000);

      const active = getActiveApprovals();
      expect(active.length).toBe(0);

      vi.useRealTimers();
    });
  });

  describe('approval expiration edge cases', () => {
    it('should deny command after approval expires', () => {
      vi.useFakeTimers();

      const command = 'mo clean';
      approveCommand(command, 1000);

      // Command is approved
      expect(isCommandApproved(command)).toBe(true);
      expect(evaluatePolicy(command).allowed).toBe(true);

      // Fast-forward past expiration
      vi.advanceTimersByTime(1001);

      // Command is no longer approved
      expect(isCommandApproved(command)).toBe(false);
      expect(evaluatePolicy(command).allowed).toBe(false);
      expect(evaluatePolicy(command).requiresConfirmation).toBe(true);

      vi.useRealTimers();
    });

    it('should handle multiple approval/expiration cycles for same command', () => {
      vi.useFakeTimers();

      const command = 'mo clean';

      // First approval
      approveCommand(command, 1000);
      expect(isCommandApproved(command)).toBe(true);

      // Expire
      vi.advanceTimersByTime(1001);
      expect(isCommandApproved(command)).toBe(false);

      // Second approval with different expiration
      approveCommand(command, 2000);
      expect(isCommandApproved(command)).toBe(true);

      // Partial time advance (should still be approved)
      vi.advanceTimersByTime(1000);
      expect(isCommandApproved(command)).toBe(true);

      // Full expiration
      vi.advanceTimersByTime(1001);
      expect(isCommandApproved(command)).toBe(false);

      vi.useRealTimers();
    });

    it('should handle approval without expiration (permanent until revoked)', () => {
      vi.useFakeTimers();

      const command = 'mo clean';
      approveCommand(command); // No expiration time

      expect(isCommandApproved(command)).toBe(true);

      // Advance time significantly
      vi.advanceTimersByTime(1000000);

      // Should still be approved (no expiration)
      expect(isCommandApproved(command)).toBe(true);

      // But can be manually revoked
      revokeApproval(command);
      expect(isCommandApproved(command)).toBe(false);

      vi.useRealTimers();
    });

    it('should clear expired approvals when checking approval status', () => {
      vi.useFakeTimers();

      approveCommand('mo clean', 1000);
      approveCommand('mo optimize', 1000);

      expect(getActiveApprovals().length).toBe(2);

      // Advance time past expiration
      vi.advanceTimersByTime(1001);

      // Checking one command should clean up both expired approvals
      expect(isCommandApproved('mo clean')).toBe(false);
      expect(getActiveApprovals().length).toBe(0);

      vi.useRealTimers();
    });

    it('should maintain separate expiration times for different commands', () => {
      vi.useFakeTimers();

      approveCommand('mo clean', 1000);
      approveCommand('mo optimize', 2000);
      approveCommand('mo purge', 3000);

      // After 1.5 seconds, only 'mo clean' should be expired
      vi.advanceTimersByTime(1500);

      expect(isCommandApproved('mo clean')).toBe(false);
      expect(isCommandApproved('mo optimize')).toBe(true);
      expect(isCommandApproved('mo purge')).toBe(true);

      // After another 1 second, 'mo optimize' should also be expired
      vi.advanceTimersByTime(1000);

      expect(isCommandApproved('mo clean')).toBe(false);
      expect(isCommandApproved('mo optimize')).toBe(false);
      expect(isCommandApproved('mo purge')).toBe(true);

      vi.useRealTimers();
    });

    it('should allow re-approval of previously expired command', () => {
      vi.useFakeTimers();

      const command = 'mo clean';

      // Approve and expire
      approveCommand(command, 1000);
      vi.advanceTimersByTime(1001);
      expect(isCommandApproved(command)).toBe(false);

      // Re-approve
      approveCommand(command, 2000);
      expect(isCommandApproved(command)).toBe(true);
      expect(evaluatePolicy(command).allowed).toBe(true);

      vi.useRealTimers();
    });
  });

  describe('evaluatePolicy', () => {
    it('should allow safe commands immediately', () => {
      const decision = evaluatePolicy('mo status');

      expect(decision.allowed).toBe(true);
      expect(decision.classification).toBe('safe');
      expect(decision.requiresConfirmation).toBe(false);
      expect(decision.requiresDryRun).toBe(false);
    });

    it('should allow dry-run commands immediately', () => {
      const decision = evaluatePolicy('mo clean --dry-run');

      expect(decision.allowed).toBe(true);
      expect(decision.classification).toBe('safe');
      expect(decision.requiresConfirmation).toBe(false);
    });

    it('should require dry-run for destructive commands that support it', () => {
      const decision = evaluatePolicy('mo clean');

      expect(decision.allowed).toBe(false);
      expect(decision.classification).toBe('destructive');
      expect(decision.requiresConfirmation).toBe(true);
      expect(decision.requiresDryRun).toBe(true);
      expect(decision.dryRunCommand).toBe('mo clean --dry-run');
    });

    it('should allow destructive commands after approval', () => {
      const command = 'mo clean';

      approveCommand(command);

      const decision = evaluatePolicy(command);

      expect(decision.allowed).toBe(true);
      expect(decision.requiresConfirmation).toBe(false);
    });

    it('should require confirmation for unknown commands', () => {
      const decision = evaluatePolicy('mo foobar');

      expect(decision.allowed).toBe(false);
      expect(decision.classification).toBe('requires-confirmation');
      expect(decision.requiresConfirmation).toBe(true);
      expect(decision.requiresDryRun).toBe(false);
    });

    it('should allow unknown commands after approval', () => {
      const command = 'mo foobar';

      approveCommand(command);

      const decision = evaluatePolicy(command);

      expect(decision.allowed).toBe(true);
    });

    it('should require confirmation for destructive commands without dry-run support', () => {
      const decision = evaluatePolicy('mo uninstall Slack');

      expect(decision.allowed).toBe(false);
      expect(decision.classification).toBe('destructive');
      expect(decision.requiresConfirmation).toBe(true);
      expect(decision.requiresDryRun).toBe(false);
    });
  });

  describe('ConfirmationRequiredError', () => {
    it('should create error with command and decision', () => {
      const decision = evaluatePolicy('mo clean');
      const error = new ConfirmationRequiredError('mo clean', decision);

      expect(error.name).toBe('ConfirmationRequiredError');
      expect(error.command).toBe('mo clean');
      expect(error.decision).toBe(decision);
      expect(error.message).toContain('confirmation');
    });
  });
});
