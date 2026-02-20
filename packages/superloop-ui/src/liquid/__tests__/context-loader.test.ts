import { afterEach, beforeEach, describe, expect, it } from "vitest";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { loadSuperloopContext } from "../context-loader";
import { emptyContext } from "../views/types";

describe("loadSuperloopContext contract", () => {
  let repoRoot: string;

  beforeEach(async () => {
    repoRoot = await fs.mkdtemp(path.join(os.tmpdir(), "superloop-ui-context-"));
  });

  afterEach(async () => {
    await fs.rm(repoRoot, { recursive: true, force: true });
  });

  it("returns empty context when no loop can be resolved", async () => {
    const context = await loadSuperloopContext({ repoRoot });
    expect(context).toEqual(emptyContext);
  });

  it("loads loop context from run summary, tests, tasks, and events", async () => {
    const loopId = "contract-loop";
    const loopDir = path.join(repoRoot, ".superloop", "loops", loopId);
    await fs.mkdir(loopDir, { recursive: true });
    await fs.mkdir(path.join(repoRoot, ".superloop"), { recursive: true });

    await fs.writeFile(
      path.join(repoRoot, ".superloop", "state.json"),
      JSON.stringify({ active: true, current_loop_id: loopId }, null, 2),
      "utf8",
    );

    await fs.writeFile(
      path.join(loopDir, "run-summary.json"),
      JSON.stringify(
        {
          loop_id: loopId,
          updated_at: "2026-02-20T12:00:00Z",
          entries: [
            {
              iteration: 2,
              started_at: "2026-02-20T11:30:00Z",
              ended_at: "2026-02-20T11:45:00Z",
              promise: { matched: false },
              gates: {
                tests: "failed",
                checklist: "passed",
                evidence: "passed",
                approval: "pending",
              },
              completion_ok: false,
            },
          ],
        },
        null,
        2,
      ),
      "utf8",
    );

    await fs.writeFile(
      path.join(loopDir, "test-status.json"),
      JSON.stringify(
        {
          ok: false,
          skipped: false,
          failures: [
            {
              name: "should run contract test",
              message: "expected true to be false",
              file: "tests/contract.test.ts",
            },
          ],
        },
        null,
        2,
      ),
      "utf8",
    );

    await fs.writeFile(
      path.join(loopDir, "PHASE_1.MD"),
      [
        "# Phase 1",
        "- [x] Implement baseline",
        "- [ ] Add edge handling",
      ].join("\n"),
      "utf8",
    );

    await fs.writeFile(
      path.join(loopDir, "events.jsonl"),
      [
        JSON.stringify({ event: "usage", data: { role: "implementer", cost_usd: 0.8 } }),
        JSON.stringify({ event: "usage", data: { role: "tester", cost_usd: 0.45 } }),
        JSON.stringify({ event: "iteration_start", iteration: 2 }),
      ].join("\n"),
      "utf8",
    );

    const context = await loadSuperloopContext({ repoRoot, loopId });

    expect(context.loopId).toBe(loopId);
    expect(context.active).toBe(true);
    expect(context.iteration).toBe(2);
    expect(context.gates.tests).toBe("failed");
    expect(context.testFailures).toHaveLength(1);
    expect(context.taskProgress).toEqual({ total: 2, completed: 1, percent: 50 });
    expect(context.cost.totalUsd).toBeCloseTo(1.25, 6);
    expect(context.cost.breakdown).toEqual(
      expect.arrayContaining([
        { role: "implementer", cost: 0.8 },
        { role: "tester", cost: 0.45 },
      ]),
    );
    expect(context.phase).toBe("planning");
  });

  it("marks complete phase when completion_ok is true", async () => {
    const loopId = "complete-loop";
    const loopDir = path.join(repoRoot, ".superloop", "loops", loopId);
    await fs.mkdir(loopDir, { recursive: true });
    await fs.mkdir(path.join(repoRoot, ".superloop"), { recursive: true });

    await fs.writeFile(
      path.join(loopDir, "run-summary.json"),
      JSON.stringify(
        {
          loop_id: loopId,
          entries: [{ iteration: 1, promise: { matched: true }, completion_ok: true }],
        },
        null,
        2,
      ),
      "utf8",
    );

    const context = await loadSuperloopContext({ repoRoot, loopId });
    expect(context.completionOk).toBe(true);
    expect(context.phase).toBe("complete");
  });
});