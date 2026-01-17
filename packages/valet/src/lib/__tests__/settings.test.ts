import { describe, it, expect, beforeEach } from 'vitest';
import {
  getSetting,
  setSetting,
  deleteSetting,
  getAllSettings,
} from '../settings';
import { mockSettings } from '../../test/setup';

describe('settings', () => {
  beforeEach(() => {
    // Clear settings before each test
    Object.keys(mockSettings).forEach(key => delete mockSettings[key]);
  });

  describe('getSetting', () => {
    it('should return null when setting does not exist', async () => {
      const value = await getSetting('nonexistent_key');
      expect(value).toBe(null);
    });

    it('should return the setting value when it exists', async () => {
      mockSettings['test_key'] = 'test_value';

      const value = await getSetting('test_key');
      expect(value).toBe('test_value');
    });
  });

  describe('setSetting', () => {
    it('should store a setting', async () => {
      await setSetting('my_key', 'my_value');

      expect(mockSettings['my_key']).toBe('my_value');
    });

    it('should update an existing setting', async () => {
      mockSettings['existing_key'] = 'old_value';

      await setSetting('existing_key', 'new_value');

      expect(mockSettings['existing_key']).toBe('new_value');
    });

    it('should persist multiple settings', async () => {
      await setSetting('key1', 'value1');
      await setSetting('key2', 'value2');
      await setSetting('key3', 'value3');

      expect(mockSettings['key1']).toBe('value1');
      expect(mockSettings['key2']).toBe('value2');
      expect(mockSettings['key3']).toBe('value3');
    });
  });

  describe('deleteSetting', () => {
    it('should delete an existing setting', async () => {
      mockSettings['delete_me'] = 'value';

      await deleteSetting('delete_me');

      expect(mockSettings['delete_me']).toBeUndefined();
    });

    it('should not throw when deleting non-existent setting', async () => {
      await expect(deleteSetting('nonexistent')).resolves.toBeUndefined();
    });

    it('should only delete the specified setting', async () => {
      mockSettings['keep_me'] = 'keep';
      mockSettings['delete_me'] = 'delete';

      await deleteSetting('delete_me');

      expect(mockSettings['keep_me']).toBe('keep');
      expect(mockSettings['delete_me']).toBeUndefined();
    });
  });

  describe('getAllSettings', () => {
    it('should return empty object when no settings exist', async () => {
      const settings = await getAllSettings();
      expect(settings).toEqual({
        voiceEnabled: 'true',
        monitoringFrequency: '30',
        notificationMode: 'critical',
        autoStart: 'false',
        diskWarningThreshold: '20',
        diskCriticalThreshold: '10',
      });
    });

    it('should return all settings with defaults', async () => {
      mockSettings['setting1'] = 'value1';
      mockSettings['setting2'] = 'value2';
      mockSettings['setting3'] = 'value3';

      const settings = await getAllSettings();

      expect(settings).toEqual({
        setting1: 'value1',
        setting2: 'value2',
        setting3: 'value3',
        voiceEnabled: 'true',
        monitoringFrequency: '30',
        notificationMode: 'critical',
        autoStart: 'false',
        diskWarningThreshold: '20',
        diskCriticalThreshold: '10',
      });
    });

    it('should not include deleted settings', async () => {
      mockSettings['keep'] = 'value1';
      mockSettings['remove'] = 'value2';

      await deleteSetting('remove');

      const settings = await getAllSettings();

      expect(settings).toEqual({
        keep: 'value1',
        voiceEnabled: 'true',
        monitoringFrequency: '30',
        notificationMode: 'critical',
        autoStart: 'false',
        diskWarningThreshold: '20',
        diskCriticalThreshold: '10',
      });
    });
  });

  describe('settings persistence workflow', () => {
    it('should persist voice enabled setting', async () => {
      await setSetting('voiceEnabled', 'true');
      const value = await getSetting('voiceEnabled');
      expect(value).toBe('true');
    });

    it('should persist monitoring frequency setting', async () => {
      await setSetting('monitoringFrequency', '30');
      const value = await getSetting('monitoringFrequency');
      expect(value).toBe('30');
    });

    it('should persist notification mode setting', async () => {
      await setSetting('notificationMode', 'critical');
      const value = await getSetting('notificationMode');
      expect(value).toBe('critical');
    });

    it('should persist auto-start setting', async () => {
      await setSetting('autoStart', 'false');
      const value = await getSetting('autoStart');
      expect(value).toBe('false');
    });

    it('should handle complete settings workflow', async () => {
      // Set initial settings
      await setSetting('voiceEnabled', 'true');
      await setSetting('monitoringFrequency', '30');
      await setSetting('notificationMode', 'critical');
      await setSetting('autoStart', 'false');

      // Verify all settings
      const allSettings = await getAllSettings();
      expect(allSettings).toEqual({
        voiceEnabled: 'true',
        monitoringFrequency: '30',
        notificationMode: 'critical',
        autoStart: 'false',
        diskWarningThreshold: '20',
        diskCriticalThreshold: '10',
      });

      // Update a setting
      await setSetting('voiceEnabled', 'false');
      const updatedVoice = await getSetting('voiceEnabled');
      expect(updatedVoice).toBe('false');

      // Delete a setting
      await deleteSetting('notificationMode');
      const deletedSetting = await getSetting('notificationMode');
      expect(deletedSetting).toBe(null);

      // Verify final state - getAllSettings returns defaults for missing settings
      const finalSettings = await getAllSettings();
      expect(finalSettings).toEqual({
        voiceEnabled: 'false',
        monitoringFrequency: '30',
        notificationMode: 'critical', // Default is applied when setting is missing
        autoStart: 'false',
        diskWarningThreshold: '20',
        diskCriticalThreshold: '10',
      });
    });
  });

  describe('disk threshold defaults', () => {
    it('should return default disk thresholds when not set', async () => {
      const settings = await getAllSettings();
      expect(settings.diskWarningThreshold).toBe('20');
      expect(settings.diskCriticalThreshold).toBe('10');
    });

    it('should use custom disk thresholds when set', async () => {
      await setSetting('diskWarningThreshold', '40');
      await setSetting('diskCriticalThreshold', '20');

      const settings = await getAllSettings();
      expect(settings.diskWarningThreshold).toBe('40');
      expect(settings.diskCriticalThreshold).toBe('20');
    });

    it('should fall back to defaults when disk thresholds are invalid (empty)', async () => {
      mockSettings['diskWarningThreshold'] = '';
      mockSettings['diskCriticalThreshold'] = '';

      const settings = await getAllSettings();
      expect(settings.diskWarningThreshold).toBe('20');
      expect(settings.diskCriticalThreshold).toBe('10');
    });

    it('should fall back to defaults when disk thresholds are invalid (NaN)', async () => {
      mockSettings['diskWarningThreshold'] = 'not-a-number';
      mockSettings['diskCriticalThreshold'] = 'invalid';

      const settings = await getAllSettings();
      expect(settings.diskWarningThreshold).toBe('20');
      expect(settings.diskCriticalThreshold).toBe('10');
    });

    it('should fall back to defaults when disk thresholds are invalid (negative)', async () => {
      mockSettings['diskWarningThreshold'] = '-5';
      mockSettings['diskCriticalThreshold'] = '-10';

      const settings = await getAllSettings();
      expect(settings.diskWarningThreshold).toBe('20');
      expect(settings.diskCriticalThreshold).toBe('10');
    });

    it('should fall back to defaults when disk thresholds are invalid (zero)', async () => {
      mockSettings['diskWarningThreshold'] = '0';
      mockSettings['diskCriticalThreshold'] = '0';

      const settings = await getAllSettings();
      expect(settings.diskWarningThreshold).toBe('20');
      expect(settings.diskCriticalThreshold).toBe('10');
    });
  });

  describe('edge cases', () => {
    it('should handle empty string values', async () => {
      await setSetting('empty', '');
      const value = await getSetting('empty');
      expect(value).toBe('');
    });

    it('should handle special characters in values', async () => {
      const specialValue = 'value with spaces and symbols !@#$%^&*()';
      await setSetting('special', specialValue);
      const value = await getSetting('special');
      expect(value).toBe(specialValue);
    });

    it('should handle numeric values as strings', async () => {
      await setSetting('numeric', '12345');
      const value = await getSetting('numeric');
      expect(value).toBe('12345');
    });

    it('should handle JSON-like strings', async () => {
      const jsonString = '{"nested":"value"}';
      await setSetting('json', jsonString);
      const value = await getSetting('json');
      expect(value).toBe(jsonString);
    });
  });
});
