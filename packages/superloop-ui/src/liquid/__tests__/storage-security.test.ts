import { describe, expect, it } from "vitest";

import { resolveViewDir } from "../storage";

describe("storage path hardening", () => {
  const repoRoot = "/tmp/superloop";

  it("accepts safe view names", () => {
    expect(resolveViewDir(repoRoot, "dashboard_v2")).toBe(
      "/tmp/superloop/.superloop/ui/liquid/dashboard_v2",
    );
  });

  it("rejects traversal view names", () => {
    expect(() => resolveViewDir(repoRoot, "../secrets")).toThrow(
      "Invalid view name",
    );
  });

  it("rejects slash-delimited names", () => {
    expect(() => resolveViewDir(repoRoot, "team/main")).toThrow(
      "Invalid view name",
    );
  });
});
