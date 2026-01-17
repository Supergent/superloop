/**
 * Agent Safety Policy
 * Classifies commands as destructive and manages confirmation requirements
 */

// ============================================================================
// Types
// ============================================================================

export type CommandClassification = 'safe' | 'requires-confirmation' | 'destructive';

export interface PolicyDecision {
  /** Whether the command is allowed to execute */
  allowed: boolean;
  /** Classification of the command */
  classification: CommandClassification;
  /** Whether confirmation is required before execution */
  requiresConfirmation: boolean;
  /** Reason for the decision */
  reason?: string;
  /** Whether dry-run is required first */
  requiresDryRun: boolean;
  /** Suggested dry-run command if applicable */
  dryRunCommand?: string;
}

export interface CommandApproval {
  command: string;
  timestamp: number;
  expiresAt?: number; // Optional expiration timestamp
}

// ============================================================================
// Destructive Command Patterns
// ============================================================================

/**
 * Commands that modify system state and require confirmation
 */
const DESTRUCTIVE_COMMANDS = [
  'mo clean',
  'mo uninstall',
  'mo optimize',
  'mo purge',
  'mo installer',
];

/**
 * Safe commands that can be executed without confirmation
 */
const SAFE_COMMANDS = [
  'mo status',
  'mo analyze',
];

/**
 * Commands that support --dry-run flag
 */
const DRY_RUN_COMMANDS = [
  'mo clean',
  'mo optimize',
  'mo purge',
  'mo installer',
];

// ============================================================================
// Approval Tracking
// ============================================================================

/**
 * In-memory store of one-time approvals
 * Key: normalized command string
 * Value: approval metadata
 */
const approvals = new Map<string, CommandApproval>();

/**
 * Normalize a command string for comparison
 * Removes extra whitespace and converts to lowercase
 */
function normalizeCommand(command: string): string {
  return command.trim().toLowerCase().replace(/\s+/g, ' ');
}

/**
 * Check if a command has been approved
 */
export function isCommandApproved(command: string): boolean {
  const normalized = normalizeCommand(command);
  const approval = approvals.get(normalized);

  if (!approval) {
    return false;
  }

  // Check if approval has expired
  if (approval.expiresAt && Date.now() > approval.expiresAt) {
    approvals.delete(normalized);
    return false;
  }

  return true;
}

/**
 * Grant approval for a command
 * @param command - The command to approve
 * @param durationMs - Optional duration in milliseconds (default: undefined for one-time approval)
 *
 * Note: By default, approvals are one-time use (no expiration window).
 * The caller should revoke the approval after successful execution using revokeApproval().
 */
export function approveCommand(command: string, durationMs?: number): void {
  const normalized = normalizeCommand(command);
  approvals.set(normalized, {
    command: normalized,
    timestamp: Date.now(),
    expiresAt: durationMs !== undefined ? Date.now() + durationMs : undefined,
  });
}

/**
 * Revoke approval for a command
 */
export function revokeApproval(command: string): void {
  const normalized = normalizeCommand(command);
  approvals.delete(normalized);
}

/**
 * Clear all approvals
 */
export function clearAllApprovals(): void {
  approvals.clear();
}

/**
 * Get all active approvals
 */
export function getActiveApprovals(): CommandApproval[] {
  const now = Date.now();
  const active: CommandApproval[] = [];

  for (const [key, approval] of approvals.entries()) {
    // Remove expired approvals
    if (approval.expiresAt && now > approval.expiresAt) {
      approvals.delete(key);
    } else {
      active.push(approval);
    }
  }

  return active;
}

// ============================================================================
// Command Classification
// ============================================================================

/**
 * Check if a command has a standalone dry-run flag
 * @param normalized - Normalized command string
 * @returns true if the command has --dry-run or standalone -n flag
 */
function hasDryRunFlag(normalized: string): boolean {
  const parts = normalized.split(/\s+/);

  // Reject --dry-run=<value> forms (e.g., --dry-run=false) first
  // If ANY --dry-run=<value> flag is present, treat as unsafe
  if (parts.some(part => part.startsWith('--dry-run='))) {
    return false;
  }

  // Check for standalone --dry-run flag (not --dry-run=<value>)
  if (parts.includes('--dry-run')) {
    return true;
  }

  // Check for standalone -n flag (not part of another flag like --no-confirmation)
  return parts.includes('-n');
}

/**
 * Classify a Mole command based on its potential impact
 */
export function classifyCommand(command: string): CommandClassification {
  const normalized = normalizeCommand(command);

  // Check if it's a safe command
  for (const safeCmd of SAFE_COMMANDS) {
    if (normalized.startsWith(safeCmd)) {
      return 'safe';
    }
  }

  // Check if it's a destructive command
  for (const destructiveCmd of DESTRUCTIVE_COMMANDS) {
    if (normalized.startsWith(destructiveCmd)) {
      // If it has --dry-run or standalone -n AND the command supports dry-run, it's safe
      if (hasDryRunFlag(normalized) && supportsDryRun(command)) {
        return 'safe';
      }
      return 'destructive';
    }
  }

  // Unknown commands require confirmation
  return 'requires-confirmation';
}

/**
 * Check if a command supports dry-run mode
 */
export function supportsDryRun(command: string): boolean {
  const normalized = normalizeCommand(command);

  for (const dryRunCmd of DRY_RUN_COMMANDS) {
    if (normalized.startsWith(dryRunCmd)) {
      return true;
    }
  }

  return false;
}

/**
 * Generate a dry-run version of a command
 */
export function toDryRunCommand(command: string): string {
  const normalized = normalizeCommand(command);

  // Don't add --dry-run if it already has it
  if (hasDryRunFlag(normalized)) {
    return command;
  }

  // Add --dry-run flag before any existing flags
  const parts = command.trim().split(/\s+/);

  // Strip any invalid --dry-run=<value> tokens
  const filteredParts = parts.filter(part => !part.startsWith('--dry-run='));

  const baseCmd = filteredParts[0]; // 'mo'
  const subCmd = filteredParts[1]; // 'clean', 'optimize', etc.

  if (filteredParts.length === 2) {
    return `${baseCmd} ${subCmd} --dry-run`;
  }

  // Insert --dry-run after subcommand
  return `${baseCmd} ${subCmd} --dry-run ${filteredParts.slice(2).join(' ')}`;
}

/**
 * Check if a command is currently in dry-run mode
 */
export function isDryRun(command: string): boolean {
  const normalized = normalizeCommand(command);
  return hasDryRunFlag(normalized);
}

// ============================================================================
// Policy Evaluation
// ============================================================================

/**
 * Evaluate policy for a command and return a decision
 */
export function evaluatePolicy(command: string): PolicyDecision {
  const normalized = normalizeCommand(command);
  const classification = classifyCommand(command);

  // Safe commands can execute immediately
  if (classification === 'safe') {
    return {
      allowed: true,
      classification,
      requiresConfirmation: false,
      requiresDryRun: false,
    };
  }

  // Check if command has been approved
  const isApproved = isCommandApproved(command);

  if (classification === 'destructive') {
    const isDry = isDryRun(command);
    const canDryRun = supportsDryRun(command);

    // If it's a dry-run AND the command supports dry-run, allow it
    if (isDry && canDryRun) {
      return {
        allowed: true,
        classification: 'safe', // Dry-run is safe
        requiresConfirmation: false,
        requiresDryRun: false,
      };
    }

    // If it supports dry-run and hasn't been run yet, require dry-run first
    if (canDryRun && !isApproved) {
      return {
        allowed: false,
        classification,
        requiresConfirmation: true,
        requiresDryRun: true,
        dryRunCommand: toDryRunCommand(command),
        reason: 'Destructive command requires dry-run preview and confirmation',
      };
    }

    // If approved, allow execution
    if (isApproved) {
      return {
        allowed: true,
        classification,
        requiresConfirmation: false,
        requiresDryRun: false,
      };
    }

    // Not approved, require confirmation
    return {
      allowed: false,
      classification,
      requiresConfirmation: true,
      requiresDryRun: canDryRun,
      dryRunCommand: canDryRun ? toDryRunCommand(command) : undefined,
      reason: 'Destructive command requires user confirmation',
    };
  }

  // Unknown commands require confirmation
  if (classification === 'requires-confirmation') {
    if (isApproved) {
      return {
        allowed: true,
        classification,
        requiresConfirmation: false,
        requiresDryRun: false,
      };
    }

    return {
      allowed: false,
      classification,
      requiresConfirmation: true,
      requiresDryRun: false,
      reason: 'Unknown command requires user confirmation',
    };
  }

  // Default: deny
  return {
    allowed: false,
    classification: 'destructive',
    requiresConfirmation: true,
    requiresDryRun: false,
    reason: 'Command not recognized',
  };
}

/**
 * Create a confirmation-required error for the agent to handle
 */
export class ConfirmationRequiredError extends Error {
  public readonly command: string;
  public readonly decision: PolicyDecision;

  constructor(command: string, decision: PolicyDecision) {
    super(decision.reason || 'This command requires user confirmation');
    this.name = 'ConfirmationRequiredError';
    this.command = command;
    this.decision = decision;
  }
}

// ============================================================================
// Exports
// ============================================================================

export default {
  evaluatePolicy,
  classifyCommand,
  isCommandApproved,
  approveCommand,
  revokeApproval,
  clearAllApprovals,
  getActiveApprovals,
  supportsDryRun,
  toDryRunCommand,
  isDryRun,
  ConfirmationRequiredError,
};
