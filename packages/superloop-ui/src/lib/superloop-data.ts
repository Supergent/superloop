import fs from "node:fs/promises";
import path from "node:path";

import { fileExists, readJson } from "./fs-utils.js";
import { resolveLoopDir, resolveLoopsRoot } from "./paths.js";

type RunSummaryEntry = {
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
};

type RunSummary = {
  loop_id?: string;
  updated_at?: string;
  entries?: RunSummaryEntry[];
};

type TestStatus = {
  ok?: boolean;
  skipped?: boolean;
};

type ChecklistStatus = {
  ok?: boolean;
};

export type SuperloopDataPayload = {
  loopId?: string;
  data: Record<string, string>;
};

export async function resolveLoopId(repoRoot: string, preferred?: string): Promise<string | null> {
  const loopsRoot = resolveLoopsRoot(repoRoot);
  if (!(await fileExists(loopsRoot))) {
    return null;
  }

  if (preferred) {
    const loopDir = resolveLoopDir(repoRoot, preferred);
    if (await fileExists(loopDir)) {
      return preferred;
    }
  }

  if (process.env.SUPERLOOP_LOOP_ID) {
    const envId = process.env.SUPERLOOP_LOOP_ID;
    if (envId && (await fileExists(resolveLoopDir(repoRoot, envId)))) {
      return envId;
    }
  }

  const entries = await fs.readdir(loopsRoot, { withFileTypes: true });
  const loopDirs = entries.filter((entry) => entry.isDirectory());
  if (loopDirs.length === 0) {
    return null;
  }

  const withStats = await Promise.all(
    loopDirs.map(async (entry) => {
      const dirPath = path.join(loopsRoot, entry.name);
      const stats = await fs.stat(dirPath);
      return { name: entry.name, mtimeMs: stats.mtimeMs };
    }),
  );

  withStats.sort((a, b) => b.mtimeMs - a.mtimeMs);
  return withStats[0]?.name ?? null;
}

export async function loadSuperloopData(params: {
  repoRoot: string;
  loopId?: string;
}): Promise<SuperloopDataPayload> {
  const loopId = await resolveLoopId(params.repoRoot, params.loopId);
  if (!loopId) {
    return { data: {} };
  }

  const loopDir = resolveLoopDir(params.repoRoot, loopId);
  const runSummary = await readJson<RunSummary>(path.join(loopDir, "run-summary.json"));
  const testStatus = await readJson<TestStatus>(path.join(loopDir, "test-status.json"));
  const checklistStatus = await readJson<ChecklistStatus>(
    path.join(loopDir, "checklist-status.json"),
  );

  const entry = runSummary?.entries?.[runSummary.entries.length - 1];
  const data: Record<string, string> = {
    loop_id: loopId,
    updated_at: runSummary?.updated_at ?? new Date().toISOString(),
  };

  if (entry?.iteration !== undefined) {
    data.iteration = String(entry.iteration);
  }

  if (entry?.promise?.text || entry?.promise?.expected) {
    data.promise = entry.promise.text ?? entry.promise.expected ?? "";
  }

  if (entry?.promise?.matched !== undefined) {
    data.promise_matched = entry.promise.matched ? "true" : "false";
  }

  if (entry?.gates?.tests) {
    data.test_status = entry.gates.tests;
  } else if (testStatus && typeof testStatus.ok === "boolean") {
    data.test_status = testStatus.ok ? (testStatus.skipped ? "skipped" : "ok") : "failed";
  }

  if (entry?.gates?.checklist) {
    data.checklist_status = entry.gates.checklist;
  } else if (typeof checklistStatus?.ok === "boolean") {
    data.checklist_status = checklistStatus.ok ? "ok" : "failed";
  }

  if (entry?.gates?.evidence) {
    data.evidence_status = entry.gates.evidence;
  }

  if (entry?.gates?.approval) {
    data.approval_status = entry.gates.approval;
  }

  if (entry?.completion_ok !== undefined) {
    data.completion_ok = entry.completion_ok ? "true" : "false";
  }

  if (entry?.started_at) {
    data.started_at = entry.started_at;
  }

  if (entry?.ended_at) {
    data.ended_at = entry.ended_at;
  }

  return { loopId, data };
}
