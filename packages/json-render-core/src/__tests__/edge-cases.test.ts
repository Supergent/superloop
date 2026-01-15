import { describe, it, expect, vi } from "vitest";
import { z } from "zod";
import { createCatalog, generateCatalogPrompt } from "../catalog";
import {
  evaluateVisibility,
  evaluateLogicExpression,
  visibility,
} from "../visibility";
import {
  builtInValidationFunctions,
  runValidation,
  runValidationCheck,
} from "../validation";
import { executeAction, resolveAction } from "../actions";
import { getByPath, setByPath, resolveDynamicValue } from "../types";

describe("Edge Cases: Complex Nested Visibility Conditions", () => {
  describe("deeply nested AND/OR combinations", () => {
    it("evaluates deeply nested AND within OR", () => {
      const ctx = { dataModel: { a: true, b: true, c: false, d: true } };

      const condition = {
        or: [
          { and: [{ path: "/a" }, { path: "/b" }] },
          { and: [{ path: "/c" }, { path: "/d" }] },
        ],
      };

      // First AND is true, so OR is true
      expect(evaluateVisibility(condition, ctx)).toBe(true);
    });

    it("evaluates deeply nested OR within AND", () => {
      const ctx = { dataModel: { a: true, b: false, c: false, d: true } };

      const condition = {
        and: [
          { or: [{ path: "/a" }, { path: "/b" }] },
          { or: [{ path: "/c" }, { path: "/d" }] },
        ],
      };

      // Both ORs are true, so AND is true
      expect(evaluateVisibility(condition, ctx)).toBe(true);
    });

    it("evaluates triple-nested conditions", () => {
      const ctx = {
        dataModel: { x: 5, y: 10, z: 15, admin: true, premium: true },
      };

      const condition = {
        and: [
          {
            or: [
              { and: [{ gt: [{ path: "/x" }, 0] }, { lt: [{ path: "/x" }, 10] }] },
              { gte: [{ path: "/y" }, 10] },
            ],
          },
          { path: "/admin" },
          { not: { and: [{ path: "/premium" }, { eq: [{ path: "/z" }, 0] }] } },
        ],
      };

      expect(evaluateVisibility(condition, ctx)).toBe(true);
    });
  });

  describe("mixed path, auth, and logic expressions", () => {
    it("evaluates nested path conditions within AND", () => {
      const ctx = {
        dataModel: { isPremium: true, hasAccess: true },
        authState: { isSignedIn: true },
      };

      // Note: auth conditions cannot be nested within logic expressions,
      // only path-based and comparison expressions can be nested
      const condition = {
        and: [
          { path: "/isPremium" },
          { path: "/hasAccess" },
        ],
      };

      expect(evaluateVisibility(condition, ctx)).toBe(true);
    });

    it("evaluates complex comparisons with nested paths", () => {
      const ctx = {
        dataModel: {
          user: { score: 75, threshold: 50 },
          settings: { minScore: 60 },
        },
      };

      const condition = {
        and: [
          { gt: [{ path: "/user/score" }, { path: "/settings/minScore" }] },
          { gte: [{ path: "/user/score" }, { path: "/user/threshold" }] },
        ],
      };

      expect(evaluateVisibility(condition, ctx)).toBe(true);
    });

    it("evaluates complex OR with path conditions", () => {
      const ctx = {
        dataModel: { allowAnonymous: true, isPublic: true, isAdmin: false },
        authState: { isSignedIn: false },
      };

      // Auth conditions work at top level, not nested in logic
      const condition = {
        or: [
          { path: "/isAdmin" },
          { and: [{ path: "/allowAnonymous" }, { path: "/isPublic" }] },
        ],
      };

      expect(evaluateVisibility(condition, ctx)).toBe(true);
    });
  });

  describe("edge cases in comparisons", () => {
    it("handles null and undefined values in dataModel", () => {
      const ctx = { dataModel: { nullValue: null, undefinedValue: undefined, zeroValue: 0 } };

      // resolveDynamicValue returns undefined for null/undefined paths
      // So null path resolves to undefined, not null
      expect(
        evaluateLogicExpression({ eq: [{ path: "/nullValue" }, undefined] }, ctx),
      ).toBe(false); // null !== undefined in the dataModel
      expect(
        evaluateLogicExpression({ eq: [{ path: "/zeroValue" }, 0] }, ctx),
      ).toBe(true);
      expect(
        evaluateLogicExpression({ neq: [{ path: "/nullValue" }, 5] }, ctx),
      ).toBe(true);
    });

    it("handles string and number comparisons", () => {
      const ctx = { dataModel: { str: "100", num: 100 } };

      // Type mismatch
      expect(
        evaluateLogicExpression({ eq: [{ path: "/str" }, { path: "/num" }] }, ctx),
      ).toBe(false);
      expect(
        evaluateLogicExpression({ neq: [{ path: "/str" }, { path: "/num" }] }, ctx),
      ).toBe(true);
    });

    it("handles negative numbers in comparisons", () => {
      const ctx = { dataModel: { negative: -5, zero: 0 } };

      expect(
        evaluateLogicExpression(
          { lt: [{ path: "/negative" }, { path: "/zero" }] },
          ctx,
        ),
      ).toBe(true);
      expect(
        evaluateLogicExpression({ gt: [{ path: "/zero" }, { path: "/negative" }] }, ctx),
      ).toBe(true);
    });

    it("handles floating point comparisons", () => {
      const ctx = { dataModel: { pi: 3.14159, e: 2.71828 } };

      expect(
        evaluateLogicExpression({ gt: [{ path: "/pi" }, { path: "/e" }] }, ctx),
      ).toBe(true);
      expect(
        evaluateLogicExpression({ gte: [{ path: "/pi" }, 3.14] }, ctx),
      ).toBe(true);
    });
  });
});

describe("Edge Cases: Action Error Scenarios", () => {
  describe("handler errors", () => {
    it("handles error messages with $error.message", async () => {
      const networkError = new Error("Network failed");
      const setData = vi.fn();

      await executeAction({
        action: {
          name: "fetch",
          params: {},
          onError: {
            set: {
              errorMessage: "$error.message",
              errorOccurred: true,
            },
          },
        },
        handler: vi.fn().mockRejectedValue(networkError),
        setData,
      });

      // Only $error.message is specially handled, other values are set literally
      expect(setData).toHaveBeenCalledWith("errorMessage", "Network failed");
      expect(setData).toHaveBeenCalledWith("errorOccurred", true);
    });

    it("handles timeout errors with $error.message", async () => {
      const timeoutError = new Error("Request timeout");
      const setData = vi.fn();

      await executeAction({
        action: {
          name: "slowRequest",
          params: {},
          onError: {
            set: {
              errorMsg: "$error.message",
              timedOut: true,
            },
          },
        },
        handler: vi.fn().mockRejectedValue(timeoutError),
        setData,
      });

      expect(setData).toHaveBeenCalledWith("errorMsg", "Request timeout");
      expect(setData).toHaveBeenCalledWith("timedOut", true);
    });

    it("handles errors without message property", async () => {
      const weirdError = { code: "WEIRD_ERROR" };
      const setData = vi.fn();

      await executeAction({
        action: {
          name: "test",
          params: {},
          onError: { set: { errorCode: "UNKNOWN" } },
        },
        handler: vi.fn().mockRejectedValue(weirdError),
        setData,
      });

      // Literal values are set as-is
      expect(setData).toHaveBeenCalledWith("errorCode", "UNKNOWN");
    });

    it("handles literal error values in onError set", async () => {
      const error = new Error("Failed");
      const setData = vi.fn();

      await executeAction({
        action: {
          name: "test",
          params: {},
          onError: { set: { hasError: true, defaultMessage: "Operation failed" } },
        },
        handler: vi.fn().mockRejectedValue(error),
        setData,
      });

      expect(setData).toHaveBeenCalledWith("hasError", true);
      expect(setData).toHaveBeenCalledWith("defaultMessage", "Operation failed");
    });

    it("executes onError action when provided", async () => {
      const originalError = new Error("Original");
      const executeActionFn = vi.fn().mockResolvedValue(undefined);

      // The error should be handled by onError action
      await executeAction({
        action: {
          name: "test",
          params: {},
          onError: { action: "handleError" },
        },
        handler: vi.fn().mockRejectedValue(originalError),
        setData: vi.fn(),
        executeAction: executeActionFn,
      });

      expect(executeActionFn).toHaveBeenCalledWith("handleError");
    });
  });

  describe("onSuccess handler priority", () => {
    it("executes navigate when both set and navigate are present", async () => {
      const setData = vi.fn();
      const navigate = vi.fn();

      await executeAction({
        action: {
          name: "save",
          params: {},
          onSuccess: {
            navigate: "/success",
            set: { saved: true },
          } as any, // Using 'as any' because TypeScript union doesn't allow both
        },
        handler: vi.fn().mockResolvedValue(undefined),
        setData,
        navigate,
      });

      // Only navigate is called (first if condition wins)
      expect(navigate).toHaveBeenCalledWith("/success");
      expect(setData).not.toHaveBeenCalled();
    });

    it("handles chained actions via onSuccess", async () => {
      const executeActionFn = vi.fn().mockResolvedValue(undefined);

      await executeAction({
        action: {
          name: "first",
          params: {},
          onSuccess: { action: "second" },
        },
        handler: vi.fn().mockResolvedValue(undefined),
        setData: vi.fn(),
        executeAction: executeActionFn,
      });

      expect(executeActionFn).toHaveBeenCalledWith("second");
    });
  });

  describe("action resolution edge cases", () => {
    it("resolves params with missing path references", () => {
      const resolved = resolveAction(
        {
          name: "test",
          params: {
            existing: { path: "/exists" },
            missing: { path: "/missing" },
          },
        },
        { exists: "value" },
      );

      expect(resolved.params.existing).toBe("value");
      expect(resolved.params.missing).toBeUndefined();
    });

    it("handles interpolation with missing values", () => {
      const resolved = resolveAction(
        {
          name: "test",
          confirm: {
            title: "Delete ${/user/name}",
            message: "Item ${/item/id} will be removed",
          },
        },
        {},
      );

      expect(resolved.confirm?.title).toBe("Delete ");
      expect(resolved.confirm?.message).toBe("Item  will be removed");
    });

    it("preserves complex nested params", () => {
      const complexParams = {
        user: { id: 1, settings: { theme: "dark" } },
        meta: [1, 2, 3],
      };

      const resolved = resolveAction(
        {
          name: "update",
          params: complexParams,
        },
        {},
      );

      expect(resolved.params).toEqual(complexParams);
    });
  });
});

describe("Edge Cases: Catalog Operations", () => {
  describe("catalog with no components or actions", () => {
    it("creates empty catalog", () => {
      const catalog = createCatalog({ components: {} });

      expect(catalog.componentNames).toHaveLength(0);
      expect(catalog.actionNames).toHaveLength(0);
      expect(catalog.hasComponent("anything")).toBe(false);
    });

    it("validates elements with permissive schema when catalog is empty", () => {
      const catalog = createCatalog({ components: {} });

      const element = {
        key: "1",
        type: "text",
        props: {},
      };

      // Empty catalogs use a permissive schema that accepts any type/props
      const result = catalog.validateElement(element);
      expect(result.success).toBe(true);
    });
  });

  describe("catalog with conflicting component names", () => {
    it("later component definition overwrites earlier one", () => {
      const catalog = createCatalog({
        components: {
          button: {
            props: z.object({ label: z.string() }),
            description: "First button",
          },
          button: {
            props: z.object({ text: z.string() }),
            description: "Second button",
          },
        },
      });

      const elementWithLabel = {
        key: "1",
        type: "button",
        props: { label: "Click" },
      };
      const elementWithText = {
        key: "2",
        type: "button",
        props: { text: "Click" },
      };

      // Should validate against the last definition (text property)
      expect(catalog.validateElement(elementWithLabel).success).toBe(false);
      expect(catalog.validateElement(elementWithText).success).toBe(true);
    });
  });

  describe("catalog validation edge cases", () => {
    it("validates tree structure without checking if root exists in elements", () => {
      const catalog = createCatalog({
        components: {
          text: { props: z.object({ content: z.string() }) },
        },
      });

      const treeWithMissingRoot = {
        root: "missing",
        elements: {
          "1": { key: "1", type: "text", props: { content: "Hello" } },
        },
      };

      // validateTree only checks schema structure (root is string, elements is record)
      // It doesn't validate that root key exists in elements
      const result = catalog.validateTree(treeWithMissingRoot);
      expect(result.success).toBe(true);
    });

    it("validates tree with circular references", () => {
      const catalog = createCatalog({
        components: {
          container: {
            props: z.object({ children: z.array(z.string()).optional() }),
          },
        },
      });

      // Element references itself
      const circularTree = {
        root: "1",
        elements: {
          "1": { key: "1", type: "container", props: { children: ["1"] } },
        },
      };

      // Should validate structure (doesn't check for logical cycles)
      const result = catalog.validateTree(circularTree);
      expect(result.success).toBe(true);
    });

    it("validates element with extra props", () => {
      const catalog = createCatalog({
        components: {
          text: { props: z.object({ content: z.string() }).strict() },
        },
      });

      const elementWithExtra = {
        key: "1",
        type: "text",
        props: { content: "Hello", extra: "not allowed" },
      };

      const result = catalog.validateElement(elementWithExtra);
      expect(result.success).toBe(false);
    });
  });
});

describe("Edge Cases: Validation Edge Cases", () => {
  describe("validation with unusual values", () => {
    it("handles array values with required", () => {
      expect(builtInValidationFunctions.required([1, 2, 3])).toBe(true);
      expect(builtInValidationFunctions.required([])).toBe(false);
    });

    it("handles object values with required", () => {
      expect(builtInValidationFunctions.required({ key: "value" })).toBe(true);
      expect(builtInValidationFunctions.required({})).toBe(true); // Empty objects are truthy
    });

    it("handles NaN with numeric", () => {
      expect(builtInValidationFunctions.numeric(NaN)).toBe(false);
      expect(builtInValidationFunctions.numeric(Infinity)).toBe(true);
      expect(builtInValidationFunctions.numeric(-Infinity)).toBe(true);
    });

    it("handles very long strings with minLength/maxLength", () => {
      const longString = "a".repeat(10000);

      expect(builtInValidationFunctions.minLength(longString, { min: 9999 })).toBe(
        true,
      );
      expect(
        builtInValidationFunctions.maxLength(longString, { max: 10001 }),
      ).toBe(true);
      expect(
        builtInValidationFunctions.maxLength(longString, { max: 9999 }),
      ).toBe(false);
    });

    it("handles special characters in pattern", () => {
      expect(
        builtInValidationFunctions.pattern("test@example.com", {
          pattern: "^[\\w.+-]+@[\\w.-]+\\.[a-zA-Z]{2,}$",
        }),
      ).toBe(true);
      expect(
        builtInValidationFunctions.pattern("invalid@", {
          pattern: "^[\\w.+-]+@[\\w.-]+\\.[a-zA-Z]{2,}$",
        }),
      ).toBe(false);
    });
  });

  describe("validation with missing or malformed args", () => {
    it("handles minLength without min arg", () => {
      expect(builtInValidationFunctions.minLength("test", {})).toBe(false);
      expect(
        builtInValidationFunctions.minLength("test", { min: undefined }),
      ).toBe(false);
    });

    it("handles maxLength without max arg", () => {
      expect(builtInValidationFunctions.maxLength("test", {})).toBe(false);
      expect(
        builtInValidationFunctions.maxLength("test", { max: undefined }),
      ).toBe(false);
    });

    it("handles pattern without pattern arg", () => {
      expect(builtInValidationFunctions.pattern("test", {})).toBe(false);
      expect(
        builtInValidationFunctions.pattern("test", { pattern: undefined }),
      ).toBe(false);
    });

    it("handles matches without other arg", () => {
      expect(builtInValidationFunctions.matches("test", {})).toBe(false);
    });
  });

  describe("validation with dynamic args from dataModel", () => {
    it("resolves deeply nested path for validation args", () => {
      const result = runValidationCheck(
        {
          fn: "minLength",
          args: { min: { path: "/config/validation/minLength" } },
          message: "Too short",
        },
        {
          value: "hi",
          dataModel: { config: { validation: { minLength: 5 } } },
        },
      );

      expect(result.valid).toBe(false);
    });

    it("handles missing path in validation args", () => {
      const result = runValidationCheck(
        {
          fn: "minLength",
          args: { min: { path: "/missing" } },
          message: "Too short",
        },
        { value: "test", dataModel: {} },
      );

      // Should fail when min is undefined
      expect(result.valid).toBe(false);
    });
  });

  describe("complex validation scenarios", () => {
    it("validates with conditional enabled based on complex logic", () => {
      const result = runValidation(
        {
          checks: [{ fn: "required", message: "Required" }],
          enabled: {
            and: [
              { path: "/shouldValidate" },
              { eq: [{ path: "/userType" }, "admin"] },
            ],
          },
        },
        {
          value: "",
          dataModel: { shouldValidate: true, userType: "admin" },
        },
      );

      expect(result.valid).toBe(false); // Validation runs and fails
    });

    it("skips validation with complex false condition", () => {
      const result = runValidation(
        {
          checks: [{ fn: "required", message: "Required" }],
          enabled: {
            and: [
              { path: "/shouldValidate" },
              { eq: [{ path: "/userType" }, "admin"] },
            ],
          },
        },
        {
          value: "",
          dataModel: { shouldValidate: true, userType: "user" },
        },
      );

      expect(result.valid).toBe(true); // Validation skipped
    });

    it("collects multiple errors with different types", () => {
      const result = runValidation(
        {
          checks: [
            { fn: "required", message: "Field is required" },
            { fn: "email", message: "Must be valid email" },
            { fn: "minLength", args: { min: 10 }, message: "Too short" },
          ],
        },
        { value: "", dataModel: {} },
      );

      expect(result.valid).toBe(false);
      expect(result.errors).toContain("Field is required");
      expect(result.errors).toContain("Must be valid email");
      expect(result.errors).toContain("Too short");
    });
  });

  describe("custom validation functions", () => {
    it("uses custom function that returns false", () => {
      const customFunctions = {
        alwaysFails: () => false,
      };

      const result = runValidationCheck(
        { fn: "alwaysFails", message: "Custom error" },
        { value: "anything", dataModel: {}, customFunctions },
      );

      expect(result.valid).toBe(false);
      expect(result.message).toBe("Custom error");
    });

    it("propagates errors from custom functions", () => {
      const customFunctions = {
        throwsError: () => {
          throw new Error("Validation crashed");
        },
      };

      // Errors are not caught, they propagate to the caller
      expect(() => {
        runValidationCheck(
          { fn: "throwsError", message: "Should not reach" },
          { value: "test", dataModel: {}, customFunctions },
        );
      }).toThrow("Validation crashed");
    });

    it("uses custom function with args", () => {
      const customFunctions = {
        divisibleBy: (value: unknown, args: { divisor: number }) =>
          typeof value === "number" && value % args.divisor === 0,
      };

      const validResult = runValidationCheck(
        {
          fn: "divisibleBy",
          args: { divisor: 5 },
          message: "Must be divisible by 5",
        },
        { value: 15, dataModel: {}, customFunctions },
      );

      const invalidResult = runValidationCheck(
        {
          fn: "divisibleBy",
          args: { divisor: 5 },
          message: "Must be divisible by 5",
        },
        { value: 17, dataModel: {}, customFunctions },
      );

      expect(validResult.valid).toBe(true);
      expect(invalidResult.valid).toBe(false);
    });
  });
});

describe("Edge Cases: Catalog Prompt Generation", () => {
  it("generates comprehensive prompt for catalog with all features", () => {
    const catalog = createCatalog({
      name: "TestCatalog",
      components: {
        text: {
          props: z.object({ content: z.string() }),
          description: "Display text content",
        },
        button: {
          props: z.object({ label: z.string(), onClick: z.string().optional() }),
          description: "Clickable button element",
        },
      },
      actions: {
        navigate: {
          params: z.object({ url: z.string() }),
          description: "Navigate to a URL",
        },
        submit: {
          description: "Submit a form",
        },
      },
      functions: {
        isEmail: {
          validate: (value: unknown) => typeof value === "string" && value.includes("@"),
          description: "Check if value is an email",
        },
      },
    });

    const prompt = generateCatalogPrompt(catalog);

    // Check that prompt contains all component names and descriptions
    expect(prompt).toContain("TestCatalog");
    expect(prompt).toContain("text");
    expect(prompt).toContain("Display text content");
    expect(prompt).toContain("button");
    expect(prompt).toContain("Clickable button element");

    // Check that prompt contains action information
    expect(prompt).toContain("navigate");
    expect(prompt).toContain("Navigate to a URL");
    expect(prompt).toContain("submit");
    expect(prompt).toContain("Submit a form");

    // Check that prompt contains validation documentation
    expect(prompt).toContain("Validation");
    expect(prompt).toContain("required");
    expect(prompt).toContain("email");

    // Check that prompt contains visibility documentation
    expect(prompt).toContain("Visibility");
    expect(prompt).toContain("visible");
  });

  it("generates minimal prompt for catalog with only components", () => {
    const catalog = createCatalog({
      name: "MinimalCatalog",
      components: {
        div: {
          props: z.object({}),
        },
      },
    });

    const prompt = generateCatalogPrompt(catalog);

    expect(prompt).toContain("MinimalCatalog");
    expect(prompt).toContain("div");
  });

  it("includes custom validation function names in prompt", () => {
    const catalog = createCatalog({
      components: {
        input: { props: z.object({ value: z.string() }) },
      },
      functions: {
        customValidator: {
          validate: (value) => typeof value === "string",
          description: "Custom validation function",
        },
      },
    });

    const prompt = generateCatalogPrompt(catalog);

    // Custom function names are listed, but descriptions are not included in prompt
    expect(prompt).toContain("customValidator");
    expect(prompt).toContain("Custom:");
  });

  it("generates prompt with container and text components", () => {
    const catalog = createCatalog({
      name: "LayoutCatalog",
      components: {
        container: {
          props: z.object({ padding: z.number().optional() }),
          description: "Container element",
          hasChildren: true,
        },
        text: {
          props: z.object({ content: z.string() }),
          description: "Text element",
          hasChildren: false,
        },
      },
    });

    const prompt = generateCatalogPrompt(catalog);

    expect(prompt).toContain("LayoutCatalog");
    expect(prompt).toContain("container");
    expect(prompt).toContain("Container element");
    expect(prompt).toContain("text");
    expect(prompt).toContain("Text element");
  });

  it("handles catalog with only actions and no components", () => {
    const catalog = createCatalog({
      components: {},
      actions: {
        save: {
          description: "Save data",
        },
      },
    });

    const prompt = generateCatalogPrompt(catalog);

    expect(prompt).toContain("save");
    expect(prompt).toContain("Save data");
  });
});

describe("Edge Cases: Path Operations", () => {
  describe("getByPath with unusual structures", () => {
    it("handles arrays in path", () => {
      const data = {
        items: [
          { name: "first" },
          { name: "second" },
          { name: "third" },
        ],
      };

      expect(getByPath(data, "/items/0/name")).toBe("first");
      expect(getByPath(data, "/items/2/name")).toBe("third");
      expect(getByPath(data, "/items/5/name")).toBeUndefined();
    });

    it("handles deeply nested structures", () => {
      const data = {
        a: { b: { c: { d: { e: { f: "deep" } } } } },
      };

      expect(getByPath(data, "/a/b/c/d/e/f")).toBe("deep");
    });

    it("handles paths with special characters", () => {
      const data = {
        "user-name": "John",
        "config.value": 42,
      };

      expect(getByPath(data, "/user-name")).toBe("John");
      expect(getByPath(data, "/config.value")).toBe(42);
    });

    it("returns undefined when path goes through array index out of bounds", () => {
      const data = { items: [1, 2, 3] };

      expect(getByPath(data, "/items/10")).toBeUndefined();
    });

    it("returns undefined when path goes through null", () => {
      const data = { user: null };

      expect(getByPath(data, "/user/name")).toBeUndefined();
    });

    it("returns undefined when path goes through undefined", () => {
      const data = { user: undefined };

      expect(getByPath(data, "/user/name")).toBeUndefined();
    });
  });

  describe("setByPath with unusual operations", () => {
    it("creates nested structure in empty object", () => {
      const data: Record<string, unknown> = {};

      setByPath(data, "/a/b/c/d", "deep");

      expect(
        (
          (
            (data.a as Record<string, unknown>).b as Record<string, unknown>
          ).c as Record<string, unknown>
        ).d,
      ).toBe("deep");
    });

    it("overwrites non-object values in path", () => {
      const data: Record<string, unknown> = { user: "string" };

      setByPath(data, "/user/name", "John");

      expect((data.user as Record<string, unknown>).name).toBe("John");
    });

    it("sets value at root path", () => {
      const data: Record<string, unknown> = { existing: "value" };

      setByPath(data, "/", { new: "object" });

      // Root path doesn't replace the object itself
      expect(data.existing).toBe("value");
    });

    it("handles paths with numeric-like keys", () => {
      const data: Record<string, unknown> = {};

      setByPath(data, "/items/0/value", "first");

      expect((data.items as Record<string, unknown>)["0"]).toEqual({
        value: "first",
      });
    });
  });

  describe("resolveDynamicValue edge cases", () => {
    it("resolves nested object paths", () => {
      const data = { user: { profile: { name: "Alice" } } };

      expect(resolveDynamicValue({ path: "/user/profile/name" }, data)).toBe(
        "Alice",
      );
    });

    it("returns undefined for path to non-existent nested property", () => {
      const data = { user: { name: "Bob" } };

      expect(
        resolveDynamicValue({ path: "/user/profile/name" }, data),
      ).toBeUndefined();
    });

    it("handles literal values that are objects", () => {
      const objValue = { nested: "value" };

      expect(resolveDynamicValue(objValue, {})).toEqual(objValue);
    });

    it("handles literal values that are arrays", () => {
      const arrValue = [1, 2, 3];

      expect(resolveDynamicValue(arrValue, {})).toEqual(arrValue);
    });
  });
});
