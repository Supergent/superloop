/**
 * Superloop Context Types
 *
 * The normalized data structure that the liquid interface views consume.
 * This is what gets loaded from superloop state files and passed to views.
 */

export type GateStatusValue = "passed" | "failed" | "pending" | "skipped";

export type LoopPhase = "planning" | "implementing" | "testing" | "reviewing" | "complete";

export interface GatesState {
  promise: GateStatusValue;
  tests: GateStatusValue;
  checklist: GateStatusValue;
  evidence: GateStatusValue;
  approval: GateStatusValue;
}

export interface TaskItem {
  id: string;
  title: string;
  done: boolean;
  level: number;
}

export interface TestFailure {
  name: string;
  message?: string;
  file?: string;
}

export interface Blocker {
  title: string;
  description?: string;
  source?: string;
  iteration?: number;
}

export interface CostByRole {
  role: string;
  cost: number;
}

export interface IterationSummary {
  iteration: number;
  startedAt?: string;
  endedAt?: string;
  gates: GatesState;
  completionOk: boolean;
}

export interface SuperloopContext {
  // Loop identification
  loopId: string | null;
  active: boolean;

  // Current state
  iteration: number;
  phase: LoopPhase | null;

  // Gates
  gates: GatesState;
  completionOk: boolean;

  // Tasks (from PHASE files)
  tasks: TaskItem[];
  taskProgress: {
    total: number;
    completed: number;
    percent: number;
  };

  // Test details
  testFailures: TestFailure[];

  // Blockers
  blockers: Blocker[];
  stuck: boolean;
  stuckIterations: number;

  // Cost
  cost: {
    totalUsd: number;
    iterations: number;
    breakdown: CostByRole[];
  };

  // Timing
  startedAt: string | null;
  endedAt: string | null;
  updatedAt: string;

  // History
  iterations: IterationSummary[];
}

/**
 * Empty/initial context for when no loop is active
 */
export const emptyContext: SuperloopContext = {
  loopId: null,
  active: false,
  iteration: 0,
  phase: null,
  gates: {
    promise: "pending",
    tests: "pending",
    checklist: "pending",
    evidence: "pending",
    approval: "pending",
  },
  completionOk: false,
  tasks: [],
  taskProgress: { total: 0, completed: 0, percent: 0 },
  testFailures: [],
  blockers: [],
  stuck: false,
  stuckIterations: 0,
  cost: { totalUsd: 0, iterations: 0, breakdown: [] },
  startedAt: null,
  endedAt: null,
  updatedAt: new Date().toISOString(),
  iterations: [],
};
