import { describe, it, expect, vi, beforeEach } from 'vitest';
import {
  listViews,
  loadView,
  saveVersion,
  setActiveVersion,
  loadVersion,
  deleteVersion,
  deleteView,
  loadActiveTree,
  resolveLiquidRoot
} from '../storage';
import * as fsUtils from '../../lib/fs-utils';
import fs from 'node:fs/promises';

// Mock dependencies
vi.mock('../../lib/fs-utils');
vi.mock('node:fs/promises');

describe('Liquid View Storage', () => {
  const mockRepoRoot = '/test/repo';
  const mockLiquidRoot = '/test/repo/.superloop/liquid';

  beforeEach(() => {
    vi.clearAllMocks();

    // Default mocks
    vi.mocked(fsUtils.fileExists).mockResolvedValue(false);
    vi.mocked(fsUtils.readJson).mockResolvedValue(null);
    vi.mocked(fsUtils.writeJson).mockResolvedValue(undefined);
    vi.mocked(fs.mkdir).mockResolvedValue(undefined);
    vi.mocked(fs.readdir).mockResolvedValue([]);
    vi.mocked(fs.rm).mockResolvedValue(undefined);
  });

  describe('resolveLiquidRoot', () => {
    it('returns liquid directory path', () => {
      const result = resolveLiquidRoot(mockRepoRoot);
      expect(result).toBe(`${mockRepoRoot}/.superloop/liquid`);
    });
  });

  describe('listViews', () => {
    it('returns empty array when liquid directory does not exist', async () => {
      vi.mocked(fsUtils.fileExists).mockResolvedValue(false);

      const views = await listViews(mockRepoRoot);

      expect(views).toEqual([]);
    });

    it('returns list of views with metadata', async () => {
      vi.mocked(fsUtils.fileExists).mockResolvedValue(true);
      vi.mocked(fs.readdir).mockResolvedValue([
        'dashboard.json',
        'cost-analysis.json',
        'not-a-view.txt'  // Should be filtered out
      ] as any);

      vi.mocked(fsUtils.readJson).mockImplementation(async (path) => {
        if (path.includes('dashboard.json')) {
          return {
            name: 'dashboard',
            active: { id: 'v3', tree: {}, createdAt: '2026-01-15T10:00:00Z' },
            versions: [
              { id: 'v1', tree: {}, createdAt: '2026-01-15T09:00:00Z' },
              { id: 'v2', tree: {}, createdAt: '2026-01-15T09:30:00Z' },
              { id: 'v3', tree: {}, createdAt: '2026-01-15T10:00:00Z' }
            ]
          };
        }
        if (path.includes('cost-analysis.json')) {
          return {
            name: 'cost-analysis',
            active: { id: 'v1', tree: {}, createdAt: '2026-01-15T11:00:00Z' },
            versions: [
              { id: 'v1', tree: {}, createdAt: '2026-01-15T11:00:00Z' }
            ]
          };
        }
        return null;
      });

      const views = await listViews(mockRepoRoot);

      expect(views).toHaveLength(2);
      expect(views[0]).toEqual({
        name: 'dashboard',
        activeVersion: 'v3',
        versionCount: 3
      });
      expect(views[1]).toEqual({
        name: 'cost-analysis',
        activeVersion: 'v1',
        versionCount: 1
      });
    });

    it('skips corrupted view files', async () => {
      vi.mocked(fsUtils.fileExists).mockResolvedValue(true);
      vi.mocked(fs.readdir).mockResolvedValue([
        'valid.json',
        'corrupted.json'
      ] as any);

      vi.mocked(fsUtils.readJson).mockImplementation(async (path) => {
        if (path.includes('valid.json')) {
          return {
            name: 'valid',
            active: { id: 'v1', tree: {}, createdAt: '2026-01-15T10:00:00Z' },
            versions: [{ id: 'v1', tree: {}, createdAt: '2026-01-15T10:00:00Z' }]
          };
        }
        throw new Error('Parse error');
      });

      const views = await listViews(mockRepoRoot);

      expect(views).toHaveLength(1);
      expect(views[0].name).toBe('valid');
    });
  });

  describe('loadView', () => {
    it('loads view by name', async () => {
      const mockView = {
        name: 'test-view',
        active: {
          id: 'v2',
          tree: { root: 'main', elements: {} },
          createdAt: '2026-01-15T10:00:00Z',
          prompt: 'Show me tests'
        },
        versions: [
          {
            id: 'v1',
            tree: { root: 'old', elements: {} },
            createdAt: '2026-01-15T09:00:00Z'
          },
          {
            id: 'v2',
            tree: { root: 'main', elements: {} },
            createdAt: '2026-01-15T10:00:00Z',
            prompt: 'Show me tests'
          }
        ]
      };

      vi.mocked(fsUtils.readJson).mockResolvedValue(mockView);

      const view = await loadView(mockRepoRoot, 'test-view');

      expect(view).toEqual(mockView);
      expect(vi.mocked(fsUtils.readJson)).toHaveBeenCalledWith(
        `${mockLiquidRoot}/test-view.json`
      );
    });

    it('returns null for non-existent view', async () => {
      vi.mocked(fsUtils.readJson).mockResolvedValue(null);

      const view = await loadView(mockRepoRoot, 'nonexistent');

      expect(view).toBeNull();
    });
  });

  describe('saveVersion', () => {
    it('creates new view with first version', async () => {
      vi.mocked(fsUtils.readJson).mockResolvedValue(null);
      vi.mocked(fsUtils.fileExists).mockResolvedValue(false);

      const tree = { root: 'main', elements: {} };

      await saveVersion({
        repoRoot: mockRepoRoot,
        viewName: 'new-view',
        tree,
        prompt: 'Test prompt',
        description: 'Test description'
      });

      expect(vi.mocked(fs.mkdir)).toHaveBeenCalled();
      expect(vi.mocked(fsUtils.writeJson)).toHaveBeenCalled();

      const writeCall = vi.mocked(fsUtils.writeJson).mock.calls[0];
      const savedView = writeCall[1];

      expect(savedView).toHaveProperty('name', 'new-view');
      expect(savedView).toHaveProperty('active');
      expect(savedView).toHaveProperty('versions');
      expect(savedView.versions).toHaveLength(1);
      expect(savedView.active.tree).toEqual(tree);
      expect(savedView.active.prompt).toBe('Test prompt');
    });

    it('appends version to existing view', async () => {
      const existingView = {
        name: 'existing-view',
        active: {
          id: 'v1',
          tree: { root: 'old', elements: {} },
          createdAt: '2026-01-15T09:00:00Z'
        },
        versions: [
          {
            id: 'v1',
            tree: { root: 'old', elements: {} },
            createdAt: '2026-01-15T09:00:00Z'
          }
        ]
      };

      vi.mocked(fsUtils.readJson).mockResolvedValue(existingView);

      const newTree = { root: 'new', elements: {} };

      await saveVersion({
        repoRoot: mockRepoRoot,
        viewName: 'existing-view',
        tree: newTree,
        prompt: 'Updated view'
      });

      const writeCall = vi.mocked(fsUtils.writeJson).mock.calls[0];
      const savedView = writeCall[1];

      expect(savedView.versions).toHaveLength(2);
      expect(savedView.active.id).toBe('v2');
      expect(savedView.active.tree).toEqual(newTree);
      expect(savedView.active.prompt).toBe('Updated view');
    });

    it('generates sequential version IDs', async () => {
      const existingView = {
        name: 'test',
        active: { id: 'v5', tree: {}, createdAt: '2026-01-15T09:00:00Z' },
        versions: Array.from({ length: 5 }, (_, i) => ({
          id: `v${i + 1}`,
          tree: {},
          createdAt: '2026-01-15T09:00:00Z'
        }))
      };

      vi.mocked(fsUtils.readJson).mockResolvedValue(existingView);

      await saveVersion({
        repoRoot: mockRepoRoot,
        viewName: 'test',
        tree: { root: 'main', elements: {} }
      });

      const writeCall = vi.mocked(fsUtils.writeJson).mock.calls[0];
      const savedView = writeCall[1];

      expect(savedView.active.id).toBe('v6');
      expect(savedView.versions).toHaveLength(6);
    });
  });

  describe('setActiveVersion', () => {
    it('sets active version to specified version ID', async () => {
      const view = {
        name: 'test',
        active: {
          id: 'v2',
          tree: { root: 'v2', elements: {} },
          createdAt: '2026-01-15T10:00:00Z'
        },
        versions: [
          {
            id: 'v1',
            tree: { root: 'v1', elements: {} },
            createdAt: '2026-01-15T09:00:00Z',
            prompt: 'First version'
          },
          {
            id: 'v2',
            tree: { root: 'v2', elements: {} },
            createdAt: '2026-01-15T10:00:00Z'
          }
        ]
      };

      vi.mocked(fsUtils.readJson).mockResolvedValue(view);

      await setActiveVersion(mockRepoRoot, 'test', 'v1');

      const writeCall = vi.mocked(fsUtils.writeJson).mock.calls[0];
      const savedView = writeCall[1];

      expect(savedView.active.id).toBe('v1');
      expect(savedView.active.tree).toEqual({ root: 'v1', elements: {} });
      expect(savedView.active.prompt).toBe('First version');
    });

    it('throws error for non-existent version', async () => {
      const view = {
        name: 'test',
        active: { id: 'v1', tree: {}, createdAt: '2026-01-15T09:00:00Z' },
        versions: [
          { id: 'v1', tree: {}, createdAt: '2026-01-15T09:00:00Z' }
        ]
      };

      vi.mocked(fsUtils.readJson).mockResolvedValue(view);

      await expect(
        setActiveVersion(mockRepoRoot, 'test', 'v99')
      ).rejects.toThrow();
    });

    it('throws error for non-existent view', async () => {
      vi.mocked(fsUtils.readJson).mockResolvedValue(null);

      await expect(
        setActiveVersion(mockRepoRoot, 'nonexistent', 'v1')
      ).rejects.toThrow();
    });
  });

  describe('loadVersion', () => {
    it('loads specific version by ID', async () => {
      const view = {
        name: 'test',
        active: { id: 'v2', tree: {}, createdAt: '2026-01-15T10:00:00Z' },
        versions: [
          {
            id: 'v1',
            tree: { root: 'v1', elements: {} },
            createdAt: '2026-01-15T09:00:00Z',
            prompt: 'Old version'
          },
          {
            id: 'v2',
            tree: { root: 'v2', elements: {} },
            createdAt: '2026-01-15T10:00:00Z'
          }
        ]
      };

      vi.mocked(fsUtils.readJson).mockResolvedValue(view);

      const version = await loadVersion(mockRepoRoot, 'test', 'v1');

      expect(version).toEqual({
        id: 'v1',
        tree: { root: 'v1', elements: {} },
        createdAt: '2026-01-15T09:00:00Z',
        prompt: 'Old version'
      });
    });

    it('returns null for non-existent version', async () => {
      const view = {
        name: 'test',
        active: { id: 'v1', tree: {}, createdAt: '2026-01-15T09:00:00Z' },
        versions: [
          { id: 'v1', tree: {}, createdAt: '2026-01-15T09:00:00Z' }
        ]
      };

      vi.mocked(fsUtils.readJson).mockResolvedValue(view);

      const version = await loadVersion(mockRepoRoot, 'test', 'v99');

      expect(version).toBeNull();
    });
  });

  describe('loadActiveTree', () => {
    it('loads active tree from view', async () => {
      const activeTree = { root: 'main', elements: { main: { key: 'main', type: 'Card', props: {} } } };

      const view = {
        name: 'test',
        active: {
          id: 'v1',
          tree: activeTree,
          createdAt: '2026-01-15T09:00:00Z'
        },
        versions: [
          { id: 'v1', tree: activeTree, createdAt: '2026-01-15T09:00:00Z' }
        ]
      };

      vi.mocked(fsUtils.readJson).mockResolvedValue(view);

      const tree = await loadActiveTree(mockRepoRoot, 'test');

      expect(tree).toEqual(activeTree);
    });

    it('returns null for non-existent view', async () => {
      vi.mocked(fsUtils.readJson).mockResolvedValue(null);

      const tree = await loadActiveTree(mockRepoRoot, 'nonexistent');

      expect(tree).toBeNull();
    });
  });

  describe('deleteVersion', () => {
    it('removes version from history', async () => {
      const view = {
        name: 'test',
        active: {
          id: 'v2',
          tree: { root: 'v2', elements: {} },
          createdAt: '2026-01-15T10:00:00Z'
        },
        versions: [
          { id: 'v1', tree: {}, createdAt: '2026-01-15T09:00:00Z' },
          { id: 'v2', tree: { root: 'v2', elements: {} }, createdAt: '2026-01-15T10:00:00Z' }
        ]
      };

      vi.mocked(fsUtils.readJson).mockResolvedValue(view);

      await deleteVersion(mockRepoRoot, 'test', 'v1');

      const writeCall = vi.mocked(fsUtils.writeJson).mock.calls[0];
      const savedView = writeCall[1];

      expect(savedView.versions).toHaveLength(1);
      expect(savedView.versions[0].id).toBe('v2');
    });

    it('prevents deleting active version if it is the last version', async () => {
      const view = {
        name: 'test',
        active: { id: 'v1', tree: {}, createdAt: '2026-01-15T09:00:00Z' },
        versions: [
          { id: 'v1', tree: {}, createdAt: '2026-01-15T09:00:00Z' }
        ]
      };

      vi.mocked(fsUtils.readJson).mockResolvedValue(view);

      await expect(
        deleteVersion(mockRepoRoot, 'test', 'v1')
      ).rejects.toThrow();
    });
  });

  describe('deleteView', () => {
    it('deletes entire view file', async () => {
      await deleteView(mockRepoRoot, 'test-view');

      expect(vi.mocked(fs.rm)).toHaveBeenCalledWith(
        `${mockLiquidRoot}/test-view.json`,
        { force: true }
      );
    });

    it('succeeds even if view does not exist', async () => {
      vi.mocked(fs.rm).mockResolvedValue(undefined);

      await expect(
        deleteView(mockRepoRoot, 'nonexistent')
      ).resolves.not.toThrow();
    });
  });

  describe('concurrent operations', () => {
    it('handles concurrent version saves', async () => {
      const view = {
        name: 'test',
        active: { id: 'v1', tree: {}, createdAt: '2026-01-15T09:00:00Z' },
        versions: [
          { id: 'v1', tree: {}, createdAt: '2026-01-15T09:00:00Z' }
        ]
      };

      vi.mocked(fsUtils.readJson).mockResolvedValue(view);

      // Simulate concurrent saves
      await Promise.all([
        saveVersion({
          repoRoot: mockRepoRoot,
          viewName: 'test',
          tree: { root: 'a', elements: {} }
        }),
        saveVersion({
          repoRoot: mockRepoRoot,
          viewName: 'test',
          tree: { root: 'b', elements: {} }
        })
      ]);

      // Both should complete without error
      expect(vi.mocked(fsUtils.writeJson)).toHaveBeenCalled();
    });
  });
});
