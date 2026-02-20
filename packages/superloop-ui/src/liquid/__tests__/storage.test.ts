import { afterEach, beforeEach, describe, expect, it } from "vitest";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import {
  deleteVersion,
  deleteView,
  listViews,
  loadActiveTree,
  loadView,
  saveVersion,
  setActiveVersion,
} from "../storage";

function makeTree(id: string) {
  return {
    root: id,
    elements: {
      [id]: {
        key: id,
        type: "Card",
        props: { title: id },
      },
    },
  } as any;
}

async function waitForNextVersionId() {
  await new Promise((resolve) => setTimeout(resolve, 1100));
}

describe("Liquid View Storage contract", () => {
  let repoRoot: string;

  beforeEach(async () => {
    repoRoot = await fs.mkdtemp(path.join(os.tmpdir(), "superloop-ui-storage-"));
  });

  afterEach(async () => {
    await fs.rm(repoRoot, { recursive: true, force: true });
  });

  it("persists and lists a saved view", async () => {
    await saveVersion({
      repoRoot,
      viewName: "dashboard",
      tree: makeTree("main"),
      prompt: "show me dashboard",
      description: "contract test",
    });

    const view = await loadView({ repoRoot, viewName: "dashboard" });
    expect(view).not.toBeNull();
    expect(view?.name).toBe("dashboard");
    expect(view?.versions).toHaveLength(1);
    expect(view?.active.id).toBe(view?.latest.id);

    const listed = await listViews(repoRoot);
    expect(listed).toHaveLength(1);
    expect(listed[0]?.name).toBe("dashboard");
  });

  it("supports setting active version and loading active tree", async () => {
    await saveVersion({
      repoRoot,
      viewName: "timeline",
      tree: makeTree("v1"),
    });

    await waitForNextVersionId();

    await saveVersion({
      repoRoot,
      viewName: "timeline",
      tree: makeTree("v2"),
    });

    const view = await loadView({ repoRoot, viewName: "timeline" });
    expect(view).not.toBeNull();
    const firstVersionId = view?.versions[0]?.id;
    expect(firstVersionId).toBeTruthy();

    await setActiveVersion({
      repoRoot,
      viewName: "timeline",
      versionId: firstVersionId ?? null,
    });

    const activeTree = await loadActiveTree({ repoRoot, viewName: "timeline" });
    expect(activeTree).not.toBeNull();
    expect(activeTree?.root).toBe("v1");
  });

  it("supports deleting versions and deleting an entire view", async () => {
    await saveVersion({
      repoRoot,
      viewName: "history",
      tree: makeTree("a"),
    });

    await waitForNextVersionId();

    await saveVersion({
      repoRoot,
      viewName: "history",
      tree: makeTree("b"),
    });

    const beforeDelete = await loadView({ repoRoot, viewName: "history" });
    expect(beforeDelete?.versions).toHaveLength(2);

    const firstId = beforeDelete?.versions[0]?.id;
    expect(firstId).toBeTruthy();

    await deleteVersion({
      repoRoot,
      viewName: "history",
      versionId: firstId ?? "",
    });

    const afterDelete = await loadView({ repoRoot, viewName: "history" });
    expect(afterDelete?.versions).toHaveLength(1);

    await deleteView({ repoRoot, viewName: "history" });
    const deleted = await loadView({ repoRoot, viewName: "history" });
    expect(deleted).toBeNull();
  });
});