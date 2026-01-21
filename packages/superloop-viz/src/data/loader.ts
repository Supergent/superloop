/**
 * Data Loader for Superloop State
 *
 * Loads state from:
 * 1. Test fixtures at tests/fixtures/state/
 * 2. Live data from .superloop/state.json
 */

import { type LoopState, type LoopPhase, type GatesState, emptyState } from '../types';

interface RawState {
  status: string;
  loop_id?: string;
  iteration?: number;
  phase?: string;
  last_updated?: string;
  started_at?: string;
  stuck_count?: number;
  stuck_reason?: string;
  gates?: Partial<GatesState>;
}

/**
 * Normalize raw state from JSON files to our LoopState type
 */
function normalizeState(raw: RawState): LoopState {
  // Map phase names (files use "implementer", etc.)
  const phase = raw.phase as LoopPhase | null;

  return {
    status: raw.status as LoopState['status'],
    loopId: raw.loop_id ?? null,
    iteration: raw.iteration ?? 0,
    phase: phase ?? null,
    gates: {
      promise: raw.gates?.promise ?? 'pending',
      tests: raw.gates?.tests ?? 'pending',
      checklist: raw.gates?.checklist ?? 'pending',
      evidence: raw.gates?.evidence ?? 'pending',
      approval: raw.gates?.approval ?? 'pending',
    },
    stuckCount: raw.stuck_count ?? 0,
    stuckReason: raw.stuck_reason ?? null,
    updatedAt: raw.last_updated ?? new Date().toISOString(),
  };
}

/**
 * Load state from a fixture file
 */
export async function loadFixture(name: string): Promise<LoopState> {
  try {
    // In a real app, this would fetch from the server
    // For the prototype, we'll use fetch to load from fixtures
    const response = await fetch(`/fixtures/state/${name}/state.json`);
    if (!response.ok) {
      console.warn(`Failed to load fixture: ${name}`);
      return emptyState;
    }
    const raw = await response.json();
    return normalizeState(raw);
  } catch (error) {
    console.warn(`Error loading fixture ${name}:`, error);
    return emptyState;
  }
}

/**
 * Load live state from .superloop directory
 */
export async function loadLiveState(): Promise<LoopState> {
  try {
    const response = await fetch('/.superloop/state.json');
    if (!response.ok) {
      return emptyState;
    }
    const raw = await response.json();
    return normalizeState(raw);
  } catch {
    return emptyState;
  }
}

/**
 * Available fixture names for demo mode
 */
export const FIXTURE_NAMES = [
  'idle',
  'in-progress',
  'test-failures',
  'stuck',
  'awaiting-approval',
  'complete',
] as const;

export type FixtureName = (typeof FIXTURE_NAMES)[number];
