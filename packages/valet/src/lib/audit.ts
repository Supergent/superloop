/**
 * Audit event logging and retrieval
 * Wraps the backend get_audit_events Tauri command
 */

import { invoke } from '@tauri-apps/api/core';
import { ActivityLogEntry } from '../components/ActivityLog';

/**
 * Backend audit event structure (from Tauri)
 * Matches the Rust AuditEvent in src-tauri/src/audit.rs
 */
export interface BackendAuditEvent {
  type: string;
  command: string;
  reason?: string;
  exitCode?: number;
  timestamp: string;
}

/**
 * Frontend audit event structure with parsed timestamp
 */
export interface AuditEvent extends Omit<BackendAuditEvent, 'timestamp'> {
  id: string;
  timestamp: number;
}

/**
 * Get audit events from the backend
 */
export async function getAuditEvents(limit?: number): Promise<AuditEvent[]> {
  try {
    const events = await invoke<BackendAuditEvent[]>('get_audit_events', { limit });
    // Convert backend events with string timestamps to frontend format with numeric timestamps
    return events.map((event, index) => ({
      id: `${event.timestamp}-${index}`,
      type: event.type,
      command: event.command,
      reason: event.reason,
      exitCode: event.exitCode,
      timestamp: new Date(event.timestamp).getTime(),
    }));
  } catch (error) {
    console.error('Failed to get audit events:', error);
    return [];
  }
}

/**
 * Log an audit event to the backend
 */
export async function logAuditEvent(
  type: string,
  command: string,
  options?: {
    reason?: string;
    exitCode?: number;
  }
): Promise<void> {
  try {
    const event: BackendAuditEvent = {
      type,
      command,
      reason: options?.reason,
      exitCode: options?.exitCode,
      timestamp: new Date().toISOString(),
    };
    await invoke('log_audit_event', { event });
  } catch (error) {
    console.error('Failed to log audit event:', error);
  }
}

/**
 * Convert backend audit events to ActivityLogEntry format
 */
export function convertToActivityLogEntries(events: AuditEvent[]): ActivityLogEntry[] {
  return events.map((event) => ({
    id: event.id,
    timestamp: event.timestamp,
    type: mapEventTypeToActivityType(event.type, event.command),
    description: buildDescription(event),
    details: event.reason,
  }));
}

/**
 * Build a user-friendly description from audit event
 */
function buildDescription(event: AuditEvent): string {
  const commandDisplay = event.command || 'unknown command';

  switch (event.type) {
    case 'command_approved':
      return `Approved: ${commandDisplay}`;
    case 'command_rejected':
      return `Rejected: ${commandDisplay}`;
    case 'command_executed':
      const status = event.exitCode === 0 ? 'succeeded' : 'failed';
      return `Executed: ${commandDisplay} (${status})`;
    default:
      return commandDisplay;
  }
}

/**
 * Map backend event types to ActivityLogEntry types
 * Infers type from the command string
 */
function mapEventTypeToActivityType(
  eventType: string,
  command?: string
): ActivityLogEntry['type'] {
  const cmd = command?.toLowerCase() || '';

  if (cmd.includes('clean')) return 'clean';
  if (cmd.includes('optimize')) return 'optimize';
  if (cmd.includes('scan') || cmd.includes('analyze')) return 'scan';
  if (cmd.includes('uninstall')) return 'uninstall';
  return 'other';
}
