/**
 * Superloop Context Loader
 *
 * Loads and normalizes superloop state from files into a SuperloopContext.
 * This is what powers the liquid interface data binding.
 */

import fs from "node:fs/promises";
import path from "node:path";

import { fileExists, readJson } from "../lib/fs-utils.js";
import { resolveLoopDir, resolveLoopsRoot } from "../lib/paths.js";
import { resolveLoopId } from "../lib/superloop-data.js";

import {
  type SuperloopContext,
  type GatesState,
  type GateStatusValue,
  type TaskItem,
  type TestFailure,
  type Blocker,
  type CostByRole,
  type IterationSummary,
  type LoopPhase,
  emptyContext,
} from "./views/types.js";
import { normalizeGateStatus } from "./views/defaults.js";

// ===================
// File Types
// ===================

interface RunSummaryEntry {
  iteration?: number;
  started_at?: string;
  ended_at?: string;
  promise?: {
    expected?: string;
    text?: string;
    matched?: boolean;
  };
  gates?: {
    tests?: string;
    checklist?: string;
    evidence?: string;
    approval?: string;
  };
  completion_ok?: boolean;
}

interface RunSummary {
  loop_id?: string;
  updated_at?: string;
  entries?: RunSummaryEntry[];
}

interface StateJson {
  active?: boolean;
  loop_index?: number;
  iteration?: number;
  current_loop_id?: string;
  updated_at?: string;
}

interface TestStatusJson {
  ok?: boolean;
  skipped?: boolean;
  failures?: Array<{
    name?: string;
    message?: string;
    file?: string;
  }>;
}

interface UsageEvent {
  timestamp?: string;
  event?: string;
  data?: {
    role?: string;
    model?: string;
    input_tokens?: number;
    output_tokens?: number;
    thinking_tokens?: number;
    cost_usd?: number;
  };
}

// ===================
// Main Loader
// ===================

export async function loadSuperloopContext(params: {
  repoRoot: string;
  loopId?: string;
}): Promise<SuperloopContext> {
  // Resolve the active loop
  const loopId = await resolveLoopId(params.repoRoot, params.loopId);
  if (!loopId) {
    return { ...emptyContext };
  }

  const loopDir = resolveLoopDir(params.repoRoot, loopId);

  // Load all data sources in parallel
  const [runSummary, stateJson, testStatus, tasks, events] = await Promise.all([
    readJson<RunSummary>(path.join(loopDir, "run-summary.json")),
    readJson<StateJson>(path.join(params.repoRoot, ".superloop", "state.json")),
    readJson<TestStatusJson>(path.join(loopDir, "test-status.json")),
    loadTasks(loopDir),
    loadEvents(loopDir),
  ]);

  // Get latest entry from run summary
  const latestEntry = runSummary?.entries?.[runSummary.entries.length - 1];

  // Determine if loop is active
  const active = stateJson?.active ?? false;

  // Build gates state
  const gates = buildGatesState(latestEntry, testStatus);

  // Calculate task progress
  const completedTasks = tasks.filter((t) => t.done).length;
  const taskProgress = {
    total: tasks.length,
    completed: completedTasks,
    percent: tasks.length > 0 ? Math.round((completedTasks / tasks.length) * 100) : 0,
  };

  // Extract test failures
  const testFailures = extractTestFailures(testStatus);

  // Calculate cost from events
  const cost = calculateCost(events);

  // Detect stuck state
  const { stuck, stuckIterations } = detectStuck(runSummary?.entries ?? []);

  // Build iteration history
  const iterations = buildIterationHistory(runSummary?.entries ?? []);

  // Determine phase
  const phase = determinePhase(gates, latestEntry?.completion_ok ?? false);

  return {
    loopId,
    active,
    iteration: latestEntry?.iteration ?? 0,
    phase,
    gates,
    completionOk: latestEntry?.completion_ok ?? false,
    tasks,
    taskProgress,
    testFailures,
    blockers: [], // TODO: Extract from implementer.md, review.md
    stuck,
    stuckIterations,
    cost,
    startedAt: latestEntry?.started_at ?? null,
    endedAt: latestEntry?.ended_at ?? null,
    updatedAt: runSummary?.updated_at ?? new Date().toISOString(),
    iterations,
  };
}

// ===================
// Helpers
// ===================

function buildGatesState(
  entry: RunSummaryEntry | undefined,
  testStatus: TestStatusJson | null,
): GatesState {
  return {
    promise: entry?.promise?.matched ? "passed" : "pending",
    tests: testStatus
      ? testStatus.ok
        ? testStatus.skipped
          ? "skipped"
          : "passed"
        : "failed"
      : normalizeGateStatus(entry?.gates?.tests),
    checklist: normalizeGateStatus(entry?.gates?.checklist),
    evidence: normalizeGateStatus(entry?.gates?.evidence),
    approval: normalizeGateStatus(entry?.gates?.approval),
  };
}

function extractTestFailures(testStatus: TestStatusJson | null): TestFailure[] {
  if (!testStatus?.failures) {
    return [];
  }
  return testStatus.failures.map((f) => ({
    name: f.name ?? "Unknown test",
    message: f.message,
    file: f.file,
  }));
}

function calculateCost(events: UsageEvent[]): {
  totalUsd: number;
  iterations: number;
  breakdown: CostByRole[];
} {
  const byRole: Record<string, number> = {};
  let totalUsd = 0;
  const iterationsSeen = new Set<number>();

  for (const event of events) {
    if (event.event === "usage" && event.data?.cost_usd) {
      totalUsd += event.data.cost_usd;
      if (event.data.role) {
        byRole[event.data.role] = (byRole[event.data.role] ?? 0) + event.data.cost_usd;
      }
    }
    if (event.event === "iteration_start" && typeof (event as any).iteration === "number") {
      iterationsSeen.add((event as any).iteration);
    }
  }

  const breakdown: CostByRole[] = Object.entries(byRole).map(([role, cost]) => ({
    role,
    cost,
  }));

  return {
    totalUsd,
    iterations: iterationsSeen.size || 1,
    breakdown,
  };
}

function detectStuck(entries: RunSummaryEntry[]): { stuck: boolean; stuckIterations: number } {
  // Look for 3+ consecutive iterations without completion
  let consecutive = 0;
  for (let i = entries.length - 1; i >= 0; i--) {
    if (!entries[i]?.completion_ok) {
      consecutive++;
    } else {
      break;
    }
  }

  return {
    stuck: consecutive >= 3,
    stuckIterations: consecutive,
  };
}

function buildIterationHistory(entries: RunSummaryEntry[]): IterationSummary[] {
  return entries.map((entry) => ({
    iteration: entry.iteration ?? 0,
    startedAt: entry.started_at,
    endedAt: entry.ended_at,
    gates: {
      promise: entry.promise?.matched ? "passed" : "pending",
      tests: normalizeGateStatus(entry.gates?.tests),
      checklist: normalizeGateStatus(entry.gates?.checklist),
      evidence: normalizeGateStatus(entry.gates?.evidence),
      approval: normalizeGateStatus(entry.gates?.approval),
    },
    completionOk: entry.completion_ok ?? false,
  }));
}

function determinePhase(gates: GatesState, completionOk: boolean): LoopPhase | null {
  if (completionOk) {
    return "complete";
  }

  // Simple heuristic based on gate progression
  if (gates.promise === "pending") {
    return "planning";
  }
  if (gates.tests === "pending" || gates.tests === "failed") {
    return "implementing";
  }
  if (gates.checklist === "pending") {
    return "testing";
  }
  return "reviewing";
}

// ===================
// Task Loading (from PHASE files)
// ===================

async function loadTasks(loopDir: string): Promise<TaskItem[]> {
  const tasks: TaskItem[] = [];

  try {
    const entries = await fs.readdir(loopDir);
    const phaseFiles = entries.filter((f) => f.match(/^PHASE_\d+\.MD$/i));

    for (const filename of phaseFiles.sort()) {
      const content = await fs.readFile(path.join(loopDir, filename), "utf8");
      const fileTasks = parsePhaseFile(content);
      tasks.push(...fileTasks);
    }
  } catch {
    // No PHASE files or error reading
  }

  return tasks;
}

function parsePhaseFile(content: string): TaskItem[] {
  const tasks: TaskItem[] = [];
  const lines = content.split("\n");

  for (const line of lines) {
    // Match checkbox patterns: [ ], [x], [X]
    const match = line.match(/^(\s*)[-*]?\s*\[([ xX])\]\s*(.+)$/);
    if (match) {
      const indent = match[1]?.length ?? 0;
      const checked = match[2]?.toLowerCase() === "x";
      const title = match[3]?.trim() ?? "";

      tasks.push({
        id: `task-${tasks.length}`,
        title,
        done: checked,
        level: Math.floor(indent / 2),
      });
    }
  }

  return tasks;
}

// ===================
// Event Loading
// ===================

async function loadEvents(loopDir: string): Promise<UsageEvent[]> {
  const eventsPath = path.join(loopDir, "events.jsonl");

  if (!(await fileExists(eventsPath))) {
    return [];
  }

  try {
    const content = await fs.readFile(eventsPath, "utf8");
    const lines = content.trim().split("\n");

    return lines
      .map((line) => {
        try {
          return JSON.parse(line) as UsageEvent;
        } catch {
          return null;
        }
      })
      .filter((e): e is UsageEvent => e !== null);
  } catch {
    return [];
  }
}
