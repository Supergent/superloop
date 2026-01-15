import { describe, it, expect, vi } from "vitest";
import {
  resolveAction,
  executeAction,
  interpolateString,
  action,
} from "./actions";

describe("interpolateString", () => {
  it("interpolates ${path} expressions", () => {
    const data = { user: { name: "Alice" }, count: 5 };

    expect(interpolateString("Hello ${/user/name}!", data)).toBe(
      "Hello Alice!",
    );
    expect(interpolateString("${/user/name} has ${/count} items", data)).toBe(
      "Alice has 5 items",
    );
  });

  it("returns string unchanged when no variables", () => {
    expect(interpolateString("No vars here", {})).toBe("No vars here");
  });

  it("replaces missing values with empty string", () => {
    expect(interpolateString("Hello ${/missing}!", {})).toBe("Hello !");
  });

  it("handles multiple occurrences of same variable", () => {
    const data = { name: "Bob" };
    expect(interpolateString("${/name} says ${/name}", data)).toBe(
      "Bob says Bob",
    );
  });
});

describe("resolveAction", () => {
  it("resolves literal params", () => {
    const resolved = resolveAction(
      {
        name: "navigate",
        params: { url: "/home", count: 5 },
      },
      {},
    );

    expect(resolved.name).toBe("navigate");
    expect(resolved.params.url).toBe("/home");
    expect(resolved.params.count).toBe(5);
  });

  it("resolves dynamic path params", () => {
    const data = { userId: 123, settings: { theme: "dark" } };
    const resolved = resolveAction(
      {
        name: "updateUser",
        params: {
          id: { path: "/userId" },
          theme: { path: "/settings/theme" },
        },
      },
      data,
    );

    expect(resolved.params.id).toBe(123);
    expect(resolved.params.theme).toBe("dark");
  });

  it("interpolates confirmation messages", () => {
    const data = { user: { name: "Alice" } };
    const resolved = resolveAction(
      {
        name: "delete",
        confirm: {
          title: "Delete ${/user/name}",
          message: "Are you sure you want to delete ${/user/name}?",
        },
      },
      data,
    );

    expect(resolved.confirm?.title).toBe("Delete Alice");
    expect(resolved.confirm?.message).toBe(
      "Are you sure you want to delete Alice?",
    );
  });

  it("preserves onSuccess and onError handlers", () => {
    const resolved = resolveAction(
      {
        name: "save",
        onSuccess: { navigate: "/success" },
        onError: { set: { error: "$error.message" } },
      },
      {},
    );

    expect(resolved.onSuccess).toEqual({ navigate: "/success" });
    expect(resolved.onError).toEqual({ set: { error: "$error.message" } });
  });
});

describe("executeAction", () => {
  it("calls the handler with resolved params", async () => {
    const handler = vi.fn().mockResolvedValue(undefined);

    await executeAction({
      action: { name: "test", params: { value: 42 } },
      handler,
      setData: vi.fn(),
    });

    expect(handler).toHaveBeenCalledWith({ value: 42 });
  });

  it("handles onSuccess with navigate", async () => {
    const navigate = vi.fn();

    await executeAction({
      action: {
        name: "test",
        params: {},
        onSuccess: { navigate: "/success" },
      },
      handler: vi.fn().mockResolvedValue(undefined),
      setData: vi.fn(),
      navigate,
    });

    expect(navigate).toHaveBeenCalledWith("/success");
  });

  it("handles onSuccess with set", async () => {
    const setData = vi.fn();

    await executeAction({
      action: {
        name: "test",
        params: {},
        onSuccess: { set: { saved: true, message: "Done" } },
      },
      handler: vi.fn().mockResolvedValue(undefined),
      setData,
    });

    expect(setData).toHaveBeenCalledWith("saved", true);
    expect(setData).toHaveBeenCalledWith("message", "Done");
  });

  it("handles onSuccess with action", async () => {
    const executeActionFn = vi.fn();

    await executeAction({
      action: {
        name: "test",
        params: {},
        onSuccess: { action: "followUp" },
      },
      handler: vi.fn().mockResolvedValue(undefined),
      setData: vi.fn(),
      executeAction: executeActionFn,
    });

    expect(executeActionFn).toHaveBeenCalledWith("followUp");
  });

  it("handles onError with set", async () => {
    const setData = vi.fn();
    const error = new Error("Something went wrong");

    await executeAction({
      action: {
        name: "test",
        params: {},
        onError: { set: { error: "$error.message" } },
      },
      handler: vi.fn().mockRejectedValue(error),
      setData,
    });

    expect(setData).toHaveBeenCalledWith("error", "Something went wrong");
  });

  it("handles onError with action", async () => {
    const executeActionFn = vi.fn();
    const error = new Error("Failed");

    await executeAction({
      action: {
        name: "test",
        params: {},
        onError: { action: "handleError" },
      },
      handler: vi.fn().mockRejectedValue(error),
      setData: vi.fn(),
      executeAction: executeActionFn,
    });

    expect(executeActionFn).toHaveBeenCalledWith("handleError");
  });

  it("re-throws error when no onError handler", async () => {
    const error = new Error("Unhandled");

    await expect(
      executeAction({
        action: { name: "test", params: {} },
        handler: vi.fn().mockRejectedValue(error),
        setData: vi.fn(),
      }),
    ).rejects.toThrow("Unhandled");
  });
});

describe("action helper", () => {
  describe("simple", () => {
    it("creates action with name only", () => {
      const a = action.simple("navigate");

      expect(a.name).toBe("navigate");
      expect(a.params).toBeUndefined();
    });

    it("creates action with params", () => {
      const a = action.simple("navigate", { url: "/home" });

      expect(a.name).toBe("navigate");
      expect(a.params).toEqual({ url: "/home" });
    });
  });

  describe("withConfirm", () => {
    it("creates action with confirmation", () => {
      const a = action.withConfirm("delete", {
        title: "Confirm",
        message: "Are you sure?",
      });

      expect(a.name).toBe("delete");
      expect(a.confirm).toEqual({
        title: "Confirm",
        message: "Are you sure?",
      });
    });

    it("creates action with confirmation and params", () => {
      const a = action.withConfirm(
        "delete",
        { title: "Delete", message: "Delete item?" },
        { id: 123 },
      );

      expect(a.name).toBe("delete");
      expect(a.params).toEqual({ id: 123 });
      expect(a.confirm?.title).toBe("Delete");
    });
  });

  describe("withSuccess", () => {
    it("creates action with navigate success handler", () => {
      const a = action.withSuccess("save", { navigate: "/success" });

      expect(a.name).toBe("save");
      expect(a.onSuccess).toEqual({ navigate: "/success" });
    });

    it("creates action with set success handler", () => {
      const a = action.withSuccess("save", { set: { saved: true } });

      expect(a.onSuccess).toEqual({ set: { saved: true } });
    });

    it("creates action with success handler and params", () => {
      const a = action.withSuccess(
        "save",
        { navigate: "/done" },
        { data: "test" },
      );

      expect(a.params).toEqual({ data: "test" });
      expect(a.onSuccess).toEqual({ navigate: "/done" });
    });
  });
});
