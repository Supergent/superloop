import { describe, it, expect } from 'vitest';
import {
  isAffirmative,
  isNegative,
  detectConfirmation,
  extractUninstallTarget,
  classifyIntent,
  intentToPrompt,
} from '../voice/intent';

describe('voiceIntent', () => {
  describe('isAffirmative', () => {
    it('should detect affirmative responses', () => {
      expect(isAffirmative('yes')).toBe(true);
      expect(isAffirmative('yeah')).toBe(true);
      expect(isAffirmative('yep')).toBe(true);
      expect(isAffirmative('sure')).toBe(true);
      expect(isAffirmative('okay')).toBe(true);
      expect(isAffirmative('ok')).toBe(true);
      expect(isAffirmative('go ahead')).toBe(true);
      expect(isAffirmative('do it')).toBe(true);
    });

    it('should handle case-insensitive matching', () => {
      expect(isAffirmative('YES')).toBe(true);
      expect(isAffirmative('Yeah')).toBe(true);
      expect(isAffirmative('SURE')).toBe(true);
    });

    it('should reject non-affirmative responses', () => {
      expect(isAffirmative('no')).toBe(false);
      expect(isAffirmative('maybe')).toBe(false);
      expect(isAffirmative('I think so')).toBe(false);
    });
  });

  describe('isNegative', () => {
    it('should detect negative responses', () => {
      expect(isNegative('no')).toBe(true);
      expect(isNegative('nope')).toBe(true);
      expect(isNegative('nah')).toBe(true);
      expect(isNegative('cancel')).toBe(true);
      expect(isNegative('stop')).toBe(true);
      expect(isNegative('never mind')).toBe(true);
    });

    it('should handle case-insensitive matching', () => {
      expect(isNegative('NO')).toBe(true);
      expect(isNegative('Nope')).toBe(true);
      expect(isNegative('CANCEL')).toBe(true);
    });

    it('should reject non-negative responses', () => {
      expect(isNegative('yes')).toBe(false);
      expect(isNegative('maybe')).toBe(false);
      expect(isNegative('I don\'t know')).toBe(false);
    });
  });

  describe('detectConfirmation', () => {
    it('should detect yes confirmation', () => {
      expect(detectConfirmation('yes')).toBe('yes');
      expect(detectConfirmation('sure')).toBe('yes');
      expect(detectConfirmation('okay')).toBe('yes');
    });

    it('should detect no confirmation', () => {
      expect(detectConfirmation('no')).toBe('no');
      expect(detectConfirmation('nope')).toBe('no');
      expect(detectConfirmation('cancel')).toBe('no');
    });

    it('should return null for non-confirmation responses', () => {
      expect(detectConfirmation('maybe')).toBe(null);
      expect(detectConfirmation('I don\'t know')).toBe(null);
      expect(detectConfirmation('how about later?')).toBe(null);
    });
  });

  describe('extractUninstallTarget', () => {
    it('should extract app names from uninstall requests', () => {
      expect(extractUninstallTarget('Remove Slack')).toBe('Slack');
      expect(extractUninstallTarget('Uninstall Chrome')).toBe('Chrome');
      expect(extractUninstallTarget('Delete Microsoft Word')).toBe('Microsoft Word');
      expect(extractUninstallTarget('Get rid of Adobe Photoshop')).toBe('Adobe Photoshop');
    });

    it('should handle app name with "the" article', () => {
      expect(extractUninstallTarget('Remove the Slack app')).toBe('Slack');
      expect(extractUninstallTarget('Delete the Microsoft Word')).toBe('Microsoft Word');
    });

    it('should capitalize app names properly', () => {
      expect(extractUninstallTarget('remove slack')).toBe('Slack');
      expect(extractUninstallTarget('uninstall google chrome')).toBe('Google Chrome');
    });

    it('should return null for invalid patterns', () => {
      expect(extractUninstallTarget('just talking about apps')).toBe(null);
      expect(extractUninstallTarget('how do I remove?')).toBe(null);
    });
  });

  describe('classifyIntent', () => {
    it('should classify status intent', () => {
      const intent = classifyIntent('How\'s my Mac?');
      expect(intent.intent).toBe('status');
      expect(intent.confidence).toBeGreaterThan(0.8);
    });

    it('should classify clean intent', () => {
      const intent = classifyIntent('Clean my Mac');
      expect(intent.intent).toBe('clean');
      expect(intent.confidence).toBeGreaterThan(0.8);
    });

    it('should classify optimize intent', () => {
      const intent = classifyIntent('Optimize my Mac');
      expect(intent.intent).toBe('optimize');
      expect(intent.confidence).toBeGreaterThan(0.8);
    });

    it('should classify uninstall intent with app name', () => {
      const intent = classifyIntent('Remove Slack');
      expect(intent.intent).toBe('uninstall');
      expect(intent.entities?.appName).toBe('Slack');
      expect(intent.confidence).toBeGreaterThan(0.8);
    });

    it('should classify uninstall intent without app name', () => {
      const intent = classifyIntent('Remove something');
      expect(intent.intent).toBe('uninstall');
      expect(intent.confidence).toBeLessThan(0.9);
    });

    it('should classify analyze intent', () => {
      const intent = classifyIntent('Deep scan');
      expect(intent.intent).toBe('analyze');
      expect(intent.confidence).toBeGreaterThan(0.8);
    });

    it('should classify help intent', () => {
      const intent = classifyIntent('What can you do?');
      expect(intent.intent).toBe('help');
      expect(intent.confidence).toBeGreaterThan(0.7);
    });

    it('should classify unknown intent', () => {
      const intent = classifyIntent('random gibberish xyz');
      expect(intent.intent).toBe('unknown');
      expect(intent.confidence).toBe(0);
    });
  });

  describe('intentToPrompt', () => {
    it('should enhance status intent', () => {
      const intent = classifyIntent('How\'s my Mac?');
      const prompt = intentToPrompt(intent);

      expect(prompt).toContain('How\'s my Mac?');
      expect(prompt).toContain('mo status');
    });

    it('should enhance clean intent with dry-run instruction', () => {
      const intent = classifyIntent('Clean my Mac');
      const prompt = intentToPrompt(intent);

      expect(prompt).toContain('Clean my Mac');
      expect(prompt).toContain('mo clean --dry-run');
      expect(prompt).toContain('confirmation');
    });

    it('should enhance optimize intent with dry-run instruction', () => {
      const intent = classifyIntent('Optimize my Mac');
      const prompt = intentToPrompt(intent);

      expect(prompt).toContain('Optimize my Mac');
      expect(prompt).toContain('mo optimize --dry-run');
      expect(prompt).toContain('confirmation');
    });

    it('should enhance uninstall intent with quoted app name', () => {
      const intent = classifyIntent('Remove Microsoft Word');
      const prompt = intentToPrompt(intent);

      expect(prompt).toContain('Remove Microsoft Word');
      expect(prompt).toContain('"Microsoft Word"');
      expect(prompt).toContain('mo uninstall "Microsoft Word"');
    });

    it('should handle uninstall intent without app name', () => {
      const intent = classifyIntent('Remove something');
      const prompt = intentToPrompt(intent);

      expect(prompt).toContain('clarify which app');
    });

    it('should enhance analyze intent', () => {
      const intent = classifyIntent('Deep scan');
      const prompt = intentToPrompt(intent);

      expect(prompt).toContain('Deep scan');
      expect(prompt).toContain('mo analyze');
    });

    it('should enhance help intent', () => {
      const intent = classifyIntent('What can you do?');
      const prompt = intentToPrompt(intent);

      expect(prompt).toContain('What can you do?');
      expect(prompt).toContain('check Mac health');
      expect(prompt).toContain('clean up space');
    });

    it('should pass through unknown intents', () => {
      const intent = classifyIntent('random request');
      const prompt = intentToPrompt(intent);

      expect(prompt).toBe('random request');
    });
  });
});
