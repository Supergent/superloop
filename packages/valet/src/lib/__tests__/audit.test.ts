import { describe, it, expect } from 'vitest';
import { convertToActivityLogEntries } from '../audit';
import type { AuditEvent } from '../audit';
import type { ActivityLogEntry } from '../../components/ActivityLog';

describe('audit', () => {
  const createMockAuditEvent = (overrides?: Partial<AuditEvent>): AuditEvent => ({
    id: 'test-event-1',
    type: 'command_executed',
    command: 'mo status',
    timestamp: Date.now(),
    ...overrides,
  });

  describe('convertToActivityLogEntries', () => {
    it('should convert command_executed with success exit code', () => {
      const events: AuditEvent[] = [
        createMockAuditEvent({
          type: 'command_executed',
          command: 'mo clean',
          exitCode: 0,
        }),
      ];

      const entries = convertToActivityLogEntries(events);

      expect(entries).toHaveLength(1);
      expect(entries[0].type).toBe('clean');
      expect(entries[0].description).toContain('Executed: mo clean');
      expect(entries[0].description).toContain('succeeded');
    });

    it('should convert command_executed with failure exit code', () => {
      const events: AuditEvent[] = [
        createMockAuditEvent({
          type: 'command_executed',
          command: 'mo optimize',
          exitCode: 1,
        }),
      ];

      const entries = convertToActivityLogEntries(events);

      expect(entries).toHaveLength(1);
      expect(entries[0].type).toBe('optimize');
      expect(entries[0].description).toContain('Executed: mo optimize');
      expect(entries[0].description).toContain('failed');
    });

    it('should convert command_approved event', () => {
      const events: AuditEvent[] = [
        createMockAuditEvent({
          type: 'command_approved',
          command: 'mo analyze',
          reason: 'User requested disk analysis',
        }),
      ];

      const entries = convertToActivityLogEntries(events);

      expect(entries).toHaveLength(1);
      expect(entries[0].type).toBe('scan');
      expect(entries[0].description).toBe('Approved: mo analyze');
      expect(entries[0].details).toBe('User requested disk analysis');
    });

    it('should convert command_rejected event', () => {
      const events: AuditEvent[] = [
        createMockAuditEvent({
          type: 'command_rejected',
          command: 'mo uninstall Chrome',
          reason: 'User cancelled operation',
        }),
      ];

      const entries = convertToActivityLogEntries(events);

      expect(entries).toHaveLength(1);
      expect(entries[0].type).toBe('uninstall');
      expect(entries[0].description).toBe('Rejected: mo uninstall Chrome');
      expect(entries[0].details).toBe('User cancelled operation');
    });

    it('should preserve timestamps as numeric values', () => {
      const now = Date.now();
      const events: AuditEvent[] = [
        createMockAuditEvent({
          timestamp: now,
        }),
      ];

      const entries = convertToActivityLogEntries(events);

      expect(entries[0].timestamp).toBe(now);
      expect(typeof entries[0].timestamp).toBe('number');
    });

    it('should preserve event IDs', () => {
      const events: AuditEvent[] = [
        createMockAuditEvent({ id: 'event-123' }),
      ];

      const entries = convertToActivityLogEntries(events);

      expect(entries[0].id).toBe('event-123');
    });

    it('should map clean commands to clean activity type', () => {
      const events: AuditEvent[] = [
        createMockAuditEvent({ command: 'mo clean' }),
      ];

      const entries = convertToActivityLogEntries(events);

      expect(entries[0].type).toBe('clean');
    });

    it('should map optimize commands to optimize activity type', () => {
      const events: AuditEvent[] = [
        createMockAuditEvent({ command: 'mo optimize' }),
      ];

      const entries = convertToActivityLogEntries(events);

      expect(entries[0].type).toBe('optimize');
    });

    it('should map analyze commands to scan activity type', () => {
      const events: AuditEvent[] = [
        createMockAuditEvent({ command: 'mo analyze' }),
      ];

      const entries = convertToActivityLogEntries(events);

      expect(entries[0].type).toBe('scan');
    });

    it('should map status commands to scan activity type', () => {
      const events: AuditEvent[] = [
        createMockAuditEvent({ command: 'mo status' }),
      ];

      const entries = convertToActivityLogEntries(events);

      expect(entries[0].type).toBe('other');
    });

    it('should map uninstall commands to uninstall activity type', () => {
      const events: AuditEvent[] = [
        createMockAuditEvent({ command: 'mo uninstall Slack' }),
      ];

      const entries = convertToActivityLogEntries(events);

      expect(entries[0].type).toBe('uninstall');
    });

    it('should convert multiple events preserving order', () => {
      const events: AuditEvent[] = [
        createMockAuditEvent({ id: 'event-1', command: 'mo status' }),
        createMockAuditEvent({ id: 'event-2', command: 'mo clean' }),
        createMockAuditEvent({ id: 'event-3', command: 'mo optimize' }),
      ];

      const entries = convertToActivityLogEntries(events);

      expect(entries).toHaveLength(3);
      expect(entries[0].id).toBe('event-1');
      expect(entries[1].id).toBe('event-2');
      expect(entries[2].id).toBe('event-3');
      expect(entries[1].type).toBe('clean');
      expect(entries[2].type).toBe('optimize');
    });

    it('should handle events without optional fields', () => {
      const events: AuditEvent[] = [
        {
          id: 'minimal-event',
          type: 'command_executed',
          command: 'mo status',
          timestamp: Date.now(),
        },
      ];

      const entries = convertToActivityLogEntries(events);

      expect(entries).toHaveLength(1);
      expect(entries[0].details).toBeUndefined();
    });

    it('should return ActivityLogEntry objects with correct structure', () => {
      const events: AuditEvent[] = [
        createMockAuditEvent(),
      ];

      const entries = convertToActivityLogEntries(events);
      const entry = entries[0];

      // Verify the entry conforms to ActivityLogEntry interface
      expect(entry).toHaveProperty('id');
      expect(entry).toHaveProperty('timestamp');
      expect(entry).toHaveProperty('type');
      expect(entry).toHaveProperty('description');
      expect(typeof entry.id).toBe('string');
      expect(typeof entry.timestamp).toBe('number');
      expect(['clean', 'optimize', 'scan', 'uninstall', 'other']).toContain(entry.type);
      expect(typeof entry.description).toBe('string');
    });
  });
});
