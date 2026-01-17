import { vi } from 'vitest';

// Mock Tauri event system
export const listen = vi.fn(async (event: string, handler: (event: any) => void) => {
  return () => {}; // Return unlisten function
});

export const emit = vi.fn(async (event: string, payload?: any) => {
  return undefined;
});
