import { describe, it, expect, beforeEach } from 'vitest';
import {
  isOnboardingComplete,
  getOnboardingState,
  completeOnboarding,
  resetOnboarding,
} from '../onboarding';
import { mockSettings } from '../../test/setup';

describe('onboarding', () => {
  beforeEach(() => {
    // Clear settings before each test
    Object.keys(mockSettings).forEach(key => delete mockSettings[key]);
  });

  describe('isOnboardingComplete', () => {
    it('should return false when no onboarding state exists', async () => {
      const result = await isOnboardingComplete();
      expect(result).toBe(false);
    });

    it('should return true when onboarding is completed', async () => {
      // Set up completed state
      mockSettings['valet_onboarding_complete'] = JSON.stringify({
        completed: true,
        completedAt: Date.now(),
        version: '1.0',
      });

      const result = await isOnboardingComplete();
      expect(result).toBe(true);
    });

    it('should return false when onboarding is not completed', async () => {
      // Set up incomplete state
      mockSettings['valet_onboarding_complete'] = JSON.stringify({
        completed: false,
      });

      const result = await isOnboardingComplete();
      expect(result).toBe(false);
    });
  });

  describe('getOnboardingState', () => {
    it('should return default state when no state exists', async () => {
      const state = await getOnboardingState();
      expect(state).toEqual({ completed: false });
    });

    it('should return the full onboarding state', async () => {
      const expectedState = {
        completed: true,
        completedAt: 1705420800000,
        version: '1.0',
      };

      mockSettings['valet_onboarding_complete'] = JSON.stringify(expectedState);

      const state = await getOnboardingState();
      expect(state).toEqual(expectedState);
    });

    it('should handle invalid JSON gracefully', async () => {
      mockSettings['valet_onboarding_complete'] = 'invalid json';

      const state = await getOnboardingState();
      expect(state).toEqual({ completed: false });
    });
  });

  describe('completeOnboarding', () => {
    it('should mark onboarding as complete', async () => {
      await completeOnboarding();

      const state = await getOnboardingState();
      expect(state.completed).toBe(true);
      expect(state.completedAt).toBeDefined();
      expect(state.version).toBe('1.0');
    });

    it('should store completion timestamp', async () => {
      const beforeTime = Date.now();
      await completeOnboarding();
      const afterTime = Date.now();

      const state = await getOnboardingState();
      expect(state.completedAt).toBeGreaterThanOrEqual(beforeTime);
      expect(state.completedAt).toBeLessThanOrEqual(afterTime);
    });

    it('should persist state across calls', async () => {
      await completeOnboarding();

      const firstCheck = await isOnboardingComplete();
      expect(firstCheck).toBe(true);

      const secondCheck = await isOnboardingComplete();
      expect(secondCheck).toBe(true);
    });
  });

  describe('resetOnboarding', () => {
    it('should reset onboarding state to incomplete', async () => {
      // First complete onboarding
      await completeOnboarding();
      expect(await isOnboardingComplete()).toBe(true);

      // Then reset
      await resetOnboarding();
      expect(await isOnboardingComplete()).toBe(false);
    });

    it('should maintain state after reset', async () => {
      await resetOnboarding();

      const state = await getOnboardingState();
      expect(state.completed).toBe(false);
    });
  });

  describe('state transitions', () => {
    it('should transition from incomplete to complete', async () => {
      // Start incomplete
      expect(await isOnboardingComplete()).toBe(false);

      // Complete
      await completeOnboarding();
      expect(await isOnboardingComplete()).toBe(true);
    });

    it('should transition from complete to incomplete via reset', async () => {
      // Complete first
      await completeOnboarding();
      expect(await isOnboardingComplete()).toBe(true);

      // Reset
      await resetOnboarding();
      expect(await isOnboardingComplete()).toBe(false);
    });

    it('should allow multiple complete calls', async () => {
      await completeOnboarding();
      const firstState = await getOnboardingState();

      // Wait a bit to ensure different timestamp
      await new Promise(resolve => setTimeout(resolve, 10));

      await completeOnboarding();
      const secondState = await getOnboardingState();

      expect(firstState.completed).toBe(true);
      expect(secondState.completed).toBe(true);
      expect(secondState.completedAt).toBeGreaterThanOrEqual(firstState.completedAt!);
    });
  });
});
