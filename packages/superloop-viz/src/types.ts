/**
 * Superloop Visualization Types
 *
 * Simplified types for the visualization prototype.
 * Based on SuperloopContext from superloop-ui.
 */

export type GateStatus = 'passed' | 'failed' | 'pending' | 'skipped';

export type LoopPhase = 'planner' | 'implementer' | 'tester' | 'reviewer';

export type LoopStatus = 'idle' | 'in_progress' | 'stuck' | 'awaiting_approval' | 'complete';

export interface GatesState {
  promise: GateStatus;
  tests: GateStatus;
  checklist: GateStatus;
  evidence: GateStatus;
  approval: GateStatus;
}

export interface LoopState {
  status: LoopStatus;
  loopId: string | null;
  iteration: number;
  phase: LoopPhase | null;
  gates: GatesState;
  stuckCount: number;
  stuckReason: string | null;
  updatedAt: string;
}

export const PHASES: LoopPhase[] = ['planner', 'implementer', 'tester', 'reviewer'];

export const GATE_NAMES: (keyof GatesState)[] = [
  'promise',
  'tests',
  'checklist',
  'evidence',
  'approval',
];

export const emptyState: LoopState = {
  status: 'idle',
  loopId: null,
  iteration: 0,
  phase: null,
  gates: {
    promise: 'pending',
    tests: 'pending',
    checklist: 'pending',
    evidence: 'pending',
    approval: 'pending',
  },
  stuckCount: 0,
  stuckReason: null,
  updatedAt: new Date().toISOString(),
};
