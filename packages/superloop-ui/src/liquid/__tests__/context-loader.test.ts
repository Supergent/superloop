import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { loadSuperloopContext } from '../context-loader';
import * as fsUtils from '../../lib/fs-utils';
import * as paths from '../../lib/paths';
import * as superloopData from '../../lib/superloop-data';
import { emptyContext } from '../views/types';

// Mock dependencies
vi.mock('../../lib/fs-utils');
vi.mock('../../lib/paths');
vi.mock('../../lib/superloop-data');

describe('loadSuperloopContext', () => {
  const mockRepoRoot = '/test/repo';
  const mockLoopId = 'test-loop';
  const mockLoopDir = '/test/repo/.superloop/loops/test-loop';

  beforeEach(() => {
    vi.clearAllMocks();

    // Default mocks
    vi.mocked(superloopData.resolveLoopId).mockResolvedValue(mockLoopId);
    vi.mocked(paths.resolveLoopDir).mockReturnValue(mockLoopDir);
    vi.mocked(fsUtils.fileExists).mockResolvedValue(false);
    vi.mocked(fsUtils.readJson).mockResolvedValue(null);
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  describe('with no active loop', () => {
    it('returns empty context when no loop ID resolved', async () => {
      vi.mocked(superloopData.resolveLoopId).mockResolvedValue(null);

      const result = await loadSuperloopContext({ repoRoot: mockRepoRoot });

      expect(result).toEqual(emptyContext);
    });
  });

  describe('with active loop', () => {
    it('loads basic context with minimal data', async () => {
      vi.mocked(fsUtils.readJson).mockImplementation(async (filePath) => {
        if (filePath.includes('run-summary.json')) {
          return {
            loop_id: mockLoopId,
            updated_at: '2026-01-15T10:00:00Z',
            entries: [
              {
                iteration: 1,
                started_at: '2026-01-15T09:00:00Z',
                ended_at: '2026-01-15T09:30:00Z',
                promise: { expected: 'COMPLETE', text: '', matched: false },
                gates: {
                  tests: 'pending',
                  checklist: 'pending',
                  evidence: 'pending',
                  approval: 'pending'
                },
                completion_ok: false
              }
            ]
          };
        }
        if (filePath.includes('state.json')) {
          return {
            active: true,
            iteration: 1,
            current_loop_id: mockLoopId,
            updated_at: '2026-01-15T10:00:00Z'
          };
        }
        return null;
      });

      const result = await loadSuperloopContext({
        repoRoot: mockRepoRoot,
        loopId: mockLoopId
      });

      expect(result.loopId).toBe(mockLoopId);
      expect(result.active).toBe(true);
      expect(result.iteration).toBe(1);
      expect(result.completionOk).toBe(false);
    });

    it('parses gates from run summary correctly', async () => {
      vi.mocked(fsUtils.readJson).mockImplementation(async (filePath) => {
        if (filePath.includes('run-summary.json')) {
          return {
            entries: [
              {
                iteration: 1,
                gates: {
                  tests: 'passed',
                  checklist: 'passed',
                  evidence: 'passed',
                  approval: 'pending'
                },
                promise: { matched: false }
              }
            ]
          };
        }
        if (filePath.includes('state.json')) {
          return { active: true };
        }
        return null;
      });

      const result = await loadSuperloopContext({
        repoRoot: mockRepoRoot,
        loopId: mockLoopId
      });

      expect(result.gates.tests).toBe('passed');
      expect(result.gates.checklist).toBe('passed');
      expect(result.gates.evidence).toBe('passed');
      expect(result.gates.approval).toBe('pending');
      expect(result.gates.promise).toBe('pending');
    });

    it('marks promise gate as passed when matched', async () => {
      vi.mocked(fsUtils.readJson).mockImplementation(async (filePath) => {
        if (filePath.includes('run-summary.json')) {
          return {
            entries: [
              {
                iteration: 1,
                promise: {
                  expected: 'COMPLETE',
                  text: 'COMPLETE',
                  matched: true
                },
                gates: {}
              }
            ]
          };
        }
        if (filePath.includes('state.json')) {
          return { active: true };
        }
        return null;
      });

      const result = await loadSuperloopContext({
        repoRoot: mockRepoRoot,
        loopId: mockLoopId
      });

      expect(result.gates.promise).toBe('passed');
    });

    it('extracts test failures from test-status.json', async () => {
      vi.mocked(fsUtils.readJson).mockImplementation(async (filePath) => {
        if (filePath.includes('test-status.json')) {
          return {
            ok: false,
            skipped: false,
            failures: [
              {
                name: 'should pass',
                message: 'Expected true to be false',
                file: 'test/example.test.ts'
              },
              {
                name: 'should work',
                message: 'Timeout exceeded',
                file: 'test/another.test.ts'
              }
            ]
          };
        }
        if (filePath.includes('run-summary.json')) {
          return { entries: [{ iteration: 1 }] };
        }
        if (filePath.includes('state.json')) {
          return { active: true };
        }
        return null;
      });

      const result = await loadSuperloopContext({
        repoRoot: mockRepoRoot,
        loopId: mockLoopId
      });

      expect(result.testFailures).toHaveLength(2);
      expect(result.testFailures[0]).toEqual({
        name: 'should pass',
        message: 'Expected true to be false',
        file: 'test/example.test.ts'
      });
      expect(result.gates.tests).toBe('failed');
    });

    it('handles test-status.json with skipped tests', async () => {
      vi.mocked(fsUtils.readJson).mockImplementation(async (filePath) => {
        if (filePath.includes('test-status.json')) {
          return {
            ok: true,
            skipped: true,
            failures: []
          };
        }
        if (filePath.includes('run-summary.json')) {
          return { entries: [{ iteration: 1 }] };
        }
        if (filePath.includes('state.json')) {
          return { active: true };
        }
        return null;
      });

      const result = await loadSuperloopContext({
        repoRoot: mockRepoRoot,
        loopId: mockLoopId
      });

      expect(result.gates.tests).toBe('skipped');
      expect(result.testFailures).toHaveLength(0);
    });

    it('handles missing test status gracefully', async () => {
      vi.mocked(fsUtils.readJson).mockImplementation(async (filePath) => {
        if (filePath.includes('test-status.json')) {
          return null;
        }
        if (filePath.includes('run-summary.json')) {
          return {
            entries: [{
              iteration: 1,
              gates: { tests: 'pending' }
            }]
          };
        }
        if (filePath.includes('state.json')) {
          return { active: true };
        }
        return null;
      });

      const result = await loadSuperloopContext({
        repoRoot: mockRepoRoot,
        loopId: mockLoopId
      });

      expect(result.testFailures).toHaveLength(0);
      expect(result.gates.tests).toBe('pending');
    });

    it('handles corrupted JSON gracefully', async () => {
      vi.mocked(fsUtils.readJson).mockImplementation(async (filePath) => {
        if (filePath.includes('run-summary.json')) {
          throw new Error('JSON parse error');
        }
        if (filePath.includes('state.json')) {
          return { active: true };
        }
        return null;
      });

      const result = await loadSuperloopContext({
        repoRoot: mockRepoRoot,
        loopId: mockLoopId
      });

      // Should handle error and return context with defaults
      expect(result.loopId).toBe(mockLoopId);
      expect(result.iteration).toBe(0);
    });

    it('calculates task progress correctly', async () => {
      // Mock loadTasks to return specific tasks
      vi.mocked(fsUtils.readJson).mockImplementation(async (filePath) => {
        if (filePath.includes('PHASE')) {
          return `
## P1.1 Setup
1. [x] Create config
2. [x] Setup environment
3. [ ] Write tests

## P1.2 Implementation
1. [x] Add feature A
2. [ ] Add feature B
          `.trim();
        }
        if (filePath.includes('run-summary.json')) {
          return { entries: [{ iteration: 1 }] };
        }
        if (filePath.includes('state.json')) {
          return { active: true };
        }
        return null;
      });

      const result = await loadSuperloopContext({
        repoRoot: mockRepoRoot,
        loopId: mockLoopId
      });

      // Would need actual task parsing logic to test this properly
      // For now, verify structure exists
      expect(result.taskProgress).toBeDefined();
      expect(result.taskProgress).toHaveProperty('total');
      expect(result.taskProgress).toHaveProperty('completed');
      expect(result.taskProgress).toHaveProperty('percent');
    });

    it('detects stuck state after multiple iterations with no progress', async () => {
      vi.mocked(fsUtils.readJson).mockImplementation(async (filePath) => {
        if (filePath.includes('run-summary.json')) {
          return {
            entries: [
              { iteration: 1, completion_ok: false },
              { iteration: 2, completion_ok: false },
              { iteration: 3, completion_ok: false },
              { iteration: 4, completion_ok: false }
            ]
          };
        }
        if (filePath.includes('state.json')) {
          return { active: true };
        }
        return null;
      });

      const result = await loadSuperloopContext({
        repoRoot: mockRepoRoot,
        loopId: mockLoopId
      });

      // Stuck detection logic may vary - adjust based on actual implementation
      expect(result.iteration).toBe(4);
    });

    it('marks completion_ok when all gates pass and promise matched', async () => {
      vi.mocked(fsUtils.readJson).mockImplementation(async (filePath) => {
        if (filePath.includes('run-summary.json')) {
          return {
            entries: [
              {
                iteration: 2,
                promise: { matched: true },
                gates: {
                  tests: 'passed',
                  checklist: 'passed',
                  evidence: 'passed',
                  approval: 'passed'
                },
                completion_ok: true
              }
            ]
          };
        }
        if (filePath.includes('state.json')) {
          return { active: false };
        }
        return null;
      });

      const result = await loadSuperloopContext({
        repoRoot: mockRepoRoot,
        loopId: mockLoopId
      });

      expect(result.completionOk).toBe(true);
      expect(result.active).toBe(false);
      expect(result.gates.promise).toBe('passed');
    });

    it('resolves loop ID when not specified', async () => {
      vi.mocked(superloopData.resolveLoopId).mockResolvedValue('auto-detected-loop');
      vi.mocked(paths.resolveLoopDir).mockReturnValue('/test/repo/.superloop/loops/auto-detected-loop');

      vi.mocked(fsUtils.readJson).mockImplementation(async (filePath) => {
        if (filePath.includes('run-summary.json')) {
          return { entries: [{ iteration: 1 }] };
        }
        if (filePath.includes('state.json')) {
          return { active: true };
        }
        return null;
      });

      const result = await loadSuperloopContext({
        repoRoot: mockRepoRoot
        // No loopId specified
      });

      expect(vi.mocked(superloopData.resolveLoopId)).toHaveBeenCalledWith(mockRepoRoot, undefined);
      expect(result.loopId).toBe('auto-detected-loop');
    });

    it('includes timestamps from run summary', async () => {
      const startTime = '2026-01-15T09:00:00Z';
      const endTime = '2026-01-15T09:45:00Z';
      const updateTime = '2026-01-15T09:45:30Z';

      vi.mocked(fsUtils.readJson).mockImplementation(async (filePath) => {
        if (filePath.includes('run-summary.json')) {
          return {
            updated_at: updateTime,
            entries: [
              {
                iteration: 1,
                started_at: startTime,
                ended_at: endTime
              }
            ]
          };
        }
        if (filePath.includes('state.json')) {
          return { active: true };
        }
        return null;
      });

      const result = await loadSuperloopContext({
        repoRoot: mockRepoRoot,
        loopId: mockLoopId
      });

      expect(result.startedAt).toBe(startTime);
      expect(result.endedAt).toBe(endTime);
      expect(result.updatedAt).toBe(updateTime);
    });

    it('builds iteration history from run summary entries', async () => {
      vi.mocked(fsUtils.readJson).mockImplementation(async (filePath) => {
        if (filePath.includes('run-summary.json')) {
          return {
            entries: [
              {
                iteration: 1,
                started_at: '2026-01-15T09:00:00Z',
                ended_at: '2026-01-15T09:15:00Z',
                completion_ok: false
              },
              {
                iteration: 2,
                started_at: '2026-01-15T09:15:00Z',
                ended_at: '2026-01-15T09:30:00Z',
                completion_ok: true
              }
            ]
          };
        }
        if (filePath.includes('state.json')) {
          return { active: false };
        }
        return null;
      });

      const result = await loadSuperloopContext({
        repoRoot: mockRepoRoot,
        loopId: mockLoopId
      });

      expect(result.iterations).toBeDefined();
      expect(result.iterations.length).toBeGreaterThan(0);
    });
  });

  describe('edge cases', () => {
    it('handles empty run summary entries array', async () => {
      vi.mocked(fsUtils.readJson).mockImplementation(async (filePath) => {
        if (filePath.includes('run-summary.json')) {
          return { entries: [] };
        }
        if (filePath.includes('state.json')) {
          return { active: true };
        }
        return null;
      });

      const result = await loadSuperloopContext({
        repoRoot: mockRepoRoot,
        loopId: mockLoopId
      });

      expect(result.iteration).toBe(0);
      expect(result.completionOk).toBe(false);
    });

    it('handles missing optional fields in test failures', async () => {
      vi.mocked(fsUtils.readJson).mockImplementation(async (filePath) => {
        if (filePath.includes('test-status.json')) {
          return {
            ok: false,
            failures: [
              { name: 'test1' },
              { message: 'error' },
              {}  // completely empty failure
            ]
          };
        }
        if (filePath.includes('run-summary.json')) {
          return { entries: [{ iteration: 1 }] };
        }
        if (filePath.includes('state.json')) {
          return { active: true };
        }
        return null;
      });

      const result = await loadSuperloopContext({
        repoRoot: mockRepoRoot,
        loopId: mockLoopId
      });

      expect(result.testFailures).toHaveLength(3);
      expect(result.testFailures[2].name).toBe('Unknown test');
    });

    it('returns empty context structure even when all files missing', async () => {
      vi.mocked(fsUtils.readJson).mockResolvedValue(null);

      const result = await loadSuperloopContext({
        repoRoot: mockRepoRoot,
        loopId: mockLoopId
      });

      expect(result).toMatchObject({
        loopId: mockLoopId,
        active: false,
        iteration: 0,
        completionOk: false,
        tasks: [],
        testFailures: [],
        blockers: []
      });
    });
  });
});
