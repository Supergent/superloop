import { describe, it, expect } from "vitest";
import { resolveDynamicValue, getByPath, setByPath } from "./types";

describe("getByPath", () => {
  it("gets nested values with JSON pointer paths", () => {
    const data = { user: { name: "John", scores: [10, 20, 30] } };

    expect(getByPath(data, "/user/name")).toBe("John");
    expect(getByPath(data, "/user/scores/0")).toBe(10);
    expect(getByPath(data, "/user/scores/1")).toBe(20);
  });

  it("returns root object for empty or root path", () => {
    const data = { value: 42 };

    expect(getByPath(data, "/")).toBe(data);
    expect(getByPath(data, "")).toBe(data);
  });

  it("returns undefined for missing paths", () => {
    const data = { user: { name: "John" } };

    expect(getByPath(data, "/user/missing")).toBeUndefined();
    expect(getByPath(data, "/nonexistent/path")).toBeUndefined();
  });

  it("handles paths without leading slash", () => {
    const data = { user: { name: "John" } };

    expect(getByPath(data, "user/name")).toBe("John");
  });

  it("returns undefined when traversing through non-object", () => {
    const data = { value: "string" };

    expect(getByPath(data, "/value/nested")).toBeUndefined();
  });

  it("handles null values in path", () => {
    const data = { user: null };

    expect(getByPath(data, "/user/name")).toBeUndefined();
  });
});

describe("setByPath", () => {
  it("sets value at existing path", () => {
    const data: Record<string, unknown> = { user: { name: "John" } };

    setByPath(data, "/user/name", "Alice");

    expect((data.user as Record<string, unknown>).name).toBe("Alice");
  });

  it("creates intermediate objects for deep paths", () => {
    const data: Record<string, unknown> = {};

    setByPath(data, "/a/b/c", "deep");

    expect(
      ((data.a as Record<string, unknown>).b as Record<string, unknown>).c,
    ).toBe("deep");
  });

  it("handles paths without leading slash", () => {
    const data: Record<string, unknown> = {};

    setByPath(data, "user/name", "John");

    expect((data.user as Record<string, unknown>).name).toBe("John");
  });

  it("overwrites existing values", () => {
    const data: Record<string, unknown> = { count: 5 };

    setByPath(data, "/count", 10);

    expect(data.count).toBe(10);
  });

  it("handles array-like paths", () => {
    const data: Record<string, unknown> = { items: {} };

    setByPath(data, "/items/0", "first");

    expect((data.items as Record<string, unknown>)["0"]).toBe("first");
  });
});

describe("resolveDynamicValue", () => {
  it("resolves literal string values", () => {
    expect(resolveDynamicValue("hello", {})).toBe("hello");
  });

  it("resolves literal number values", () => {
    expect(resolveDynamicValue(42, {})).toBe(42);
  });

  it("resolves literal boolean values", () => {
    expect(resolveDynamicValue(true, {})).toBe(true);
    expect(resolveDynamicValue(false, {})).toBe(false);
  });

  it("resolves path references", () => {
    const data = { user: { name: "Alice" } };

    expect(resolveDynamicValue({ path: "/user/name" }, data)).toBe("Alice");
  });

  it("returns undefined for missing path references", () => {
    const data = { user: { name: "Alice" } };

    expect(resolveDynamicValue({ path: "/missing" }, data)).toBeUndefined();
  });

  it("returns undefined for null value", () => {
    expect(resolveDynamicValue(null as unknown as string, {})).toBeUndefined();
  });

  it("returns undefined for undefined value", () => {
    expect(
      resolveDynamicValue(undefined as unknown as string, {}),
    ).toBeUndefined();
  });
});
