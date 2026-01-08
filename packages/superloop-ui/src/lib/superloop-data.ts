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

type LoopEvent = {
  timestamp?: string;
  event?: string;
  iteration?: number;
  data?: Record<string, unknown>;
};

type EventFallback = {
  iteration?: string;
  promise?: string;
  promise_matched?: string;
  test_status?: string;
  checklist_status?: string;
  evidence_status?: string;
  approval_status?: string;
  completion_ok?: string;
  started_at?: string;
  ended_at?: string;
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
  const eventFallback = await loadEventFallback(loopDir);

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

  applyEventFallback(data, eventFallback);
  return { loopId, data };
}

function applyEventFallback(data: Record<string, string>, fallback: EventFallback) {
  const assignIfMissing = (key: keyof EventFallback) => {
    const value = fallback[key];
    if (value !== undefined && data[key] === undefined) {
      data[key] = value;
    }
  };

  assignIfMissing("iteration");
  assignIfMissing("promise");
  assignIfMissing("promise_matched");
  assignIfMissing("test_status");
  assignIfMissing("checklist_status");
  assignIfMissing("evidence_status");
  assignIfMissing("approval_status");
  assignIfMissing("completion_ok");
  assignIfMissing("started_at");
  assignIfMissing("ended_at");
}

async function loadEventFallback(loopDir: string): Promise<EventFallback> {
  const eventsPath = path.join(loopDir, "events.jsonl");
  if (!(await fileExists(eventsPath))) {
    return {};
  }

  let raw: string;
  try {
    raw = await fs.readFile(eventsPath, "utf8");
  } catch {
    return {};
  }

  const lines = raw.trim().split("\n");
  const fallback: EventFallback = {};
  const pending = new Set<keyof EventFallback>([
    "iteration",
    "promise",
    "promise_matched",
    "test_status",
    "checklist_status",
    "evidence_status",
    "approval_status",
    "completion_ok",
    "started_at",
    "ended_at",
  ]);

  for (let index = lines.length - 1; index >= 0; index -= 1) {
    const line = lines[index]?.trim();
    if (!line) {
      continue;
    }

    let event: LoopEvent;
    try {
      event = JSON.parse(line) as LoopEvent;
    } catch {
      continue;
    }

    if (pending.has("iteration") && typeof event.iteration === "number") {
      fallback.iteration = String(event.iteration);
      pending.delete("iteration");
    }

    const data = isRecord(event.data) ? event.data : {};

    if (event.event === "promise_checked") {
      if (pending.has("promise")) {
        const text = readString(data.text);
        const expected = readString(data.expected);
        if (text || expected) {
          fallback.promise = text ?? expected;
          pending.delete("promise");
        }
      }

      if (pending.has("promise_matched")) {
        const matched = readBoolean(data.matched);
        if (matched !== undefined) {
          fallback.promise_matched = matched ? "true" : "false";
          pending.delete("promise_matched");
        }
      }
    }

    if (event.event === "tests_end" && pending.has("test_status")) {
      const status = readString(data.status);
      if (status) {
        fallback.test_status = status;
        pending.delete("test_status");
      }
    }

    if (event.event === "checklist_end" && pending.has("checklist_status")) {
      const status = readString(data.status);
      if (status) {
        fallback.checklist_status = status;
        pending.delete("checklist_status");
      }
    }

    if (event.event === "evidence_end" && pending.has("evidence_status")) {
      const status = readString(data.status);
      if (status) {
        fallback.evidence_status = status;
        pending.delete("evidence_status");
      }
    }

    if (event.event === "gates_evaluated") {
      if (pending.has("test_status")) {
        const status = readString(data.tests);
        if (status) {
          fallback.test_status = status;
          pending.delete("test_status");
        }
      }

      if (pending.has("checklist_status")) {
        const status = readString(data.checklist);
        if (status) {
          fallback.checklist_status = status;
          pending.delete("checklist_status");
        }
      }

      if (pending.has("evidence_status")) {
        const status = readString(data.evidence);
        if (status) {
          fallback.evidence_status = status;
          pending.delete("evidence_status");
        }
      }

      if (pending.has("approval_status")) {
        const status = readString(data.approval);
        if (status) {
          fallback.approval_status = status;
          pending.delete("approval_status");
        }
      }
    }

    if (event.event === "iteration_start" && pending.has("started_at")) {
      const startedAt = readString(data.started_at) ?? readString(event.timestamp);
      if (startedAt) {
        fallback.started_at = startedAt;
        pending.delete("started_at");
      }
    }

    if (event.event === "iteration_end") {
      if (pending.has("ended_at")) {
        const endedAt = readString(data.ended_at) ?? readString(event.timestamp);
        if (endedAt) {
          fallback.ended_at = endedAt;
          pending.delete("ended_at");
        }
      }

      if (pending.has("completion_ok")) {
        const completion = readBoolean(data.completion);
        if (completion !== undefined) {
          fallback.completion_ok = completion ? "true" : "false";
          pending.delete("completion_ok");
        }
      }
    }

    if (pending.size === 0) {
      break;
    }
  }

  return fallback;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function readString(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value : undefined;
}

function readBoolean(value: unknown): boolean | undefined {
  return typeof value === "boolean" ? value : undefined;
}
