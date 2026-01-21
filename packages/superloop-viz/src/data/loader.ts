/**
 * Data Loader for Superloop State
 *
 * Loads state from the Vite dev server API endpoints:
 * - /__api/superloop/state - Current global state
 * - /__api/superloop/loops - List of available loops
 * - /__api/superloop/loops/:id/run-summary - Detailed loop data
 */

import { type LoopState, type GatesState, type LoopPhase, emptyState } from '../types';

/** Raw state.json format */
interface RawGlobalState {
  active: boolean;
  loop_index?: number;
  iteration: number;
  current_loop_id: string | null;
  updated_at: string;
}

/** Raw run-summary.json entry format */
interface RawIterationEntry {
  run_id: string;
  iteration: number;
  started_at: string;
  ended_at?: string;
  promise: {
    expected: string;
    text: string | null;
    matched: boolean;
  };
  gates: {
    tests: 'ok' | 'failed' | 'skipped';
    validation: 'ok' | 'failed' | 'skipped';
    checklist: 'ok' | 'failed' | 'skipped';
    evidence: 'ok' | 'failed' | 'skipped';
    approval: 'ok' | 'failed' | 'skipped';
  };
  stuck: {
    streak: number;
    threshold: number;
  };
  completion_ok: boolean;
  artifacts: Record<string, { path: string; exists: boolean }>;
}

interface RawRunSummary {
  version: number;
  loop_id: string;
  updated_at: string;
  entries: RawIterationEntry[];
}

/**
 * Map raw gate status to our GateStatus type
 */
function mapGateStatus(status: 'ok' | 'failed' | 'skipped'): GatesState[keyof GatesState] {
  switch (status) {
    case 'ok':
      return 'passed';
    case 'failed':
      return 'failed';
    case 'skipped':
      return 'skipped';
    default:
      return 'pending';
  }
}

/**
 * Infer current phase from artifacts in the latest iteration.
 * The phase is determined by which artifacts exist and are most recent.
 */
function inferPhase(entry: RawIterationEntry): LoopPhase | null {
  const artifacts = entry.artifacts;

  // Check artifact existence in reverse order (reviewer -> tester -> implementer -> planner)
  if (artifacts.reviewer?.exists) return 'reviewer';
  if (artifacts.test_report?.exists) return 'tester';
  if (artifacts.implementer?.exists) return 'implementer';
  if (artifacts.plan?.exists) return 'planner';

  return 'planner'; // Default to planner if loop is active
}

/**
 * Determine loop status from state and run summary
 */
function determineStatus(
  globalState: RawGlobalState,
  latestEntry?: RawIterationEntry
): LoopState['status'] {
  if (!globalState.active) {
    // Check if the last run completed successfully
    if (latestEntry?.completion_ok) {
      return 'complete';
    }
    return 'idle';
  }

  if (latestEntry) {
    // Check if stuck
    if (latestEntry.stuck.streak >= latestEntry.stuck.threshold) {
      return 'stuck';
    }

    // Check if awaiting approval (all gates passed except approval)
    const gates = latestEntry.gates;
    if (
      gates.tests === 'ok' &&
      gates.checklist === 'ok' &&
      (gates.evidence === 'ok' || gates.evidence === 'skipped') &&
      gates.approval === 'skipped'
    ) {
      // If promise matched but not yet approved
      if (latestEntry.promise.matched) {
        return 'awaiting_approval';
      }
    }
  }

  return 'in_progress';
}

/**
 * Fetch the current global state
 */
export async function fetchGlobalState(): Promise<RawGlobalState | null> {
  try {
    const response = await fetch('/__api/superloop/state');
    if (!response.ok) return null;
    return response.json();
  } catch {
    return null;
  }
}

/**
 * Fetch run summary for a specific loop
 */
export async function fetchRunSummary(loopId: string): Promise<RawRunSummary | null> {
  try {
    const response = await fetch(`/__api/superloop/loops/${loopId}/run-summary`);
    if (!response.ok) return null;
    return response.json();
  } catch {
    return null;
  }
}

/**
 * Fetch list of available loops
 */
export async function fetchLoopList(): Promise<string[]> {
  try {
    const response = await fetch('/__api/superloop/loops');
    if (!response.ok) return [];
    const data = await response.json();
    return data.loops ?? [];
  } catch {
    return [];
  }
}

/**
 * Load complete loop state by combining global state and run summary
 */
export async function loadLoopState(loopId?: string): Promise<LoopState> {
  const globalState = await fetchGlobalState();
  if (!globalState) return emptyState;

  const targetLoopId = loopId ?? globalState.current_loop_id;
  if (!targetLoopId) return emptyState;

  const runSummary = await fetchRunSummary(targetLoopId);
  const latestEntry = runSummary?.entries[runSummary.entries.length - 1];

  const status = determineStatus(globalState, latestEntry);

  return {
    status,
    loopId: targetLoopId,
    iteration: globalState.iteration,
    phase: globalState.active && latestEntry ? inferPhase(latestEntry) : null,
    gates: latestEntry
      ? {
          promise: latestEntry.promise.matched ? 'passed' : 'pending',
          tests: mapGateStatus(latestEntry.gates.tests),
          checklist: mapGateStatus(latestEntry.gates.checklist),
          evidence: mapGateStatus(latestEntry.gates.evidence),
          approval: mapGateStatus(latestEntry.gates.approval),
        }
      : emptyState.gates,
    stuckCount: latestEntry?.stuck.streak ?? 0,
    stuckReason:
      latestEntry && latestEntry.stuck.streak > 0
        ? `Stuck for ${latestEntry.stuck.streak} iteration(s)`
        : null,
    updatedAt: globalState.updated_at,
  };
}

/**
 * Load iteration history for timeline visualization
 */
export async function loadIterationHistory(
  loopId: string
): Promise<RawIterationEntry[]> {
  const runSummary = await fetchRunSummary(loopId);
  return runSummary?.entries ?? [];
}
