/**
 * Onboarding state management and persistence
 * Tracks whether the user has completed the onboarding flow
 */

import { invoke } from '@tauri-apps/api/core';

const ONBOARDING_KEY = 'valet_onboarding_complete';

export interface OnboardingState {
  completed: boolean;
  completedAt?: number;
  version?: string; // To handle future onboarding version updates
}

/**
 * Check if onboarding has been completed
 */
export async function isOnboardingComplete(): Promise<boolean> {
  try {
    const state = await getOnboardingState();
    return state.completed;
  } catch (error) {
    console.error('Failed to check onboarding state:', error);
    return false;
  }
}

/**
 * Get the full onboarding state
 */
export async function getOnboardingState(): Promise<OnboardingState> {
  try {
    const stateJson = await invoke<string | null>('get_setting_command', {
      key: ONBOARDING_KEY,
    });

    if (!stateJson) {
      return { completed: false };
    }

    return JSON.parse(stateJson);
  } catch (error) {
    console.error('Failed to get onboarding state:', error);
    return { completed: false };
  }
}

/**
 * Mark onboarding as complete
 */
export async function completeOnboarding(): Promise<void> {
  const state: OnboardingState = {
    completed: true,
    completedAt: Date.now(),
    version: '1.0',
  };

  try {
    await invoke('set_setting_command', {
      key: ONBOARDING_KEY,
      value: JSON.stringify(state),
    });
  } catch (error) {
    console.error('Failed to save onboarding state:', error);
    throw error;
  }
}

/**
 * Reset onboarding (for testing/debugging)
 */
export async function resetOnboarding(): Promise<void> {
  try {
    await invoke('set_setting_command', {
      key: ONBOARDING_KEY,
      value: JSON.stringify({ completed: false }),
    });
  } catch (error) {
    console.error('Failed to reset onboarding state:', error);
    throw error;
  }
}
