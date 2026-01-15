import { describe, it, expect, vi, beforeEach } from 'vitest';
import { fileExists, readJson } from '../fs-utils';
import fs from 'node:fs/promises';

vi.mock('node:fs/promises');

describe('fs-utils', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('fileExists', () => {
    it('returns true when file exists', async () => {
      vi.mocked(fs.access).mockResolvedValue(undefined);

      const result = await fileExists('/test/file.json');

      expect(result).toBe(true);
      expect(fs.access).toHaveBeenCalledWith('/test/file.json');
    });

    it('returns false when file does not exist', async () => {
      vi.mocked(fs.access).mockRejectedValue(new Error('ENOENT'));

      const result = await fileExists('/nonexistent/file.json');

      expect(result).toBe(false);
    });

    it('returns false on permission denied', async () => {
      vi.mocked(fs.access).mockRejectedValue(new Error('EACCES'));

      const result = await fileExists('/forbidden/file.json');

      expect(result).toBe(false);
    });
  });

  describe('readJson', () => {
    it('parses and returns JSON content', async () => {
      const testData = { foo: 'bar', baz: 123 };
      vi.mocked(fs.readFile).mockResolvedValue(JSON.stringify(testData));

      const result = await readJson<typeof testData>('/test/data.json');

      expect(result).toEqual(testData);
      expect(fs.readFile).toHaveBeenCalledWith('/test/data.json', 'utf8');
    });

    it('returns null when file does not exist', async () => {
      vi.mocked(fs.readFile).mockRejectedValue(new Error('ENOENT'));

      const result = await readJson('/nonexistent.json');

      expect(result).toBeNull();
    });

    it('returns null on invalid JSON', async () => {
      vi.mocked(fs.readFile).mockResolvedValue('{ invalid json }');

      const result = await readJson('/invalid.json');

      expect(result).toBeNull();
    });

    it('handles complex nested objects', async () => {
      const complexData = {
        users: [
          { id: 1, name: 'Alice', roles: ['admin', 'user'] },
          { id: 2, name: 'Bob', roles: ['user'] }
        ],
        settings: {
          theme: 'dark',
          notifications: { email: true, push: false }
        }
      };

      vi.mocked(fs.readFile).mockResolvedValue(JSON.stringify(complexData));

      const result = await readJson(path);

      expect(result).toEqual(complexData);
    });

    it('preserves null values in JSON', async () => {
      const data = { value: null, exists: true };
      vi.mocked(fs.readFile).mockResolvedValue(JSON.stringify(data));

      const result = await readJson('/test.json');

      expect(result).toEqual({ value: null, exists: true });
    });

    it('handles empty JSON objects', async () => {
      vi.mocked(fs.readFile).mockResolvedValue('{}');

      const result = await readJson('/empty.json');

      expect(result).toEqual({});
    });

    it('handles empty JSON arrays', async () => {
      vi.mocked(fs.readFile).mockResolvedValue('[]');

      const result = await readJson('/empty-array.json');

      expect(result).toEqual([]);
    });
  });
});
