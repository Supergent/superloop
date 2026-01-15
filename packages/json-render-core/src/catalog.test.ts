import { describe, it, expect } from "vitest";
import { z } from "zod";
import { createCatalog, generateCatalogPrompt } from "./catalog";

describe("createCatalog", () => {
  it("creates catalog with components", () => {
    const catalog = createCatalog({
      components: {
        text: {
          props: z.object({ content: z.string() }),
          description: "Display text",
        },
        button: {
          props: z.object({ label: z.string() }),
          description: "A clickable button",
        },
      },
    });

    expect(catalog.componentNames).toHaveLength(2);
    expect(catalog.hasComponent("text")).toBe(true);
    expect(catalog.hasComponent("button")).toBe(true);
    expect(catalog.hasComponent("unknown")).toBe(false);
  });

  it("creates catalog with actions", () => {
    const catalog = createCatalog({
      components: {
        button: { props: z.object({ label: z.string() }) },
      },
      actions: {
        navigate: { description: "Navigate to URL" },
        submit: { description: "Submit form" },
      },
    });

    expect(catalog.actionNames).toHaveLength(2);
    expect(catalog.hasAction("navigate")).toBe(true);
    expect(catalog.hasAction("submit")).toBe(true);
    expect(catalog.hasAction("unknown")).toBe(false);
  });

  it("creates catalog with custom validation functions", () => {
    const catalog = createCatalog({
      components: {
        input: { props: z.object({ value: z.string() }) },
      },
      functions: {
        customValidator: {
          validate: (value) => typeof value === "string" && value.length > 0,
          description: "Custom validation",
        },
      },
    });

    expect(catalog.functionNames).toHaveLength(1);
    expect(catalog.hasFunction("customValidator")).toBe(true);
  });

  it("validates elements correctly", () => {
    const catalog = createCatalog({
      components: {
        text: {
          props: z.object({ content: z.string() }),
        },
      },
    });

    const validElement = {
      key: "1",
      type: "text",
      props: { content: "Hello" },
    };
    const invalidElement = {
      key: "1",
      type: "text",
      props: { content: 123 },
    };

    expect(catalog.validateElement(validElement).success).toBe(true);
    expect(catalog.validateElement(invalidElement).success).toBe(false);
  });

  it("validates UI trees", () => {
    const catalog = createCatalog({
      components: {
        text: { props: z.object({ content: z.string() }) },
      },
    });

    const validTree = {
      root: "1",
      elements: {
        "1": { key: "1", type: "text", props: { content: "Hello" } },
      },
    };

    expect(catalog.validateTree(validTree).success).toBe(true);
  });

  it("uses default name when not provided", () => {
    const catalog = createCatalog({
      components: {
        text: { props: z.object({ content: z.string() }) },
      },
    });

    expect(catalog.name).toBe("unnamed");
  });

  it("uses provided name", () => {
    const catalog = createCatalog({
      name: "MyCatalog",
      components: {
        text: { props: z.object({ content: z.string() }) },
      },
    });

    expect(catalog.name).toBe("MyCatalog");
  });
});

describe("generateCatalogPrompt", () => {
  it("generates prompt containing catalog name", () => {
    const catalog = createCatalog({
      name: "TestCatalog",
      components: {
        text: {
          props: z.object({ content: z.string() }),
          description: "Display text content",
        },
      },
    });

    const prompt = generateCatalogPrompt(catalog);

    expect(prompt).toContain("TestCatalog");
  });

  it("includes component descriptions", () => {
    const catalog = createCatalog({
      components: {
        text: {
          props: z.object({ content: z.string() }),
          description: "Display text content",
        },
      },
    });

    const prompt = generateCatalogPrompt(catalog);

    expect(prompt).toContain("text");
    expect(prompt).toContain("Display text content");
  });

  it("includes action descriptions", () => {
    const catalog = createCatalog({
      components: {
        button: { props: z.object({ label: z.string() }) },
      },
      actions: {
        alert: { description: "Show alert message" },
      },
    });

    const prompt = generateCatalogPrompt(catalog);

    expect(prompt).toContain("alert");
    expect(prompt).toContain("Show alert message");
  });

  it("includes visibility documentation", () => {
    const catalog = createCatalog({
      components: {
        text: { props: z.object({ content: z.string() }) },
      },
    });

    const prompt = generateCatalogPrompt(catalog);

    expect(prompt).toContain("Visibility");
    expect(prompt).toContain("visible");
  });

  it("includes validation documentation", () => {
    const catalog = createCatalog({
      components: {
        text: { props: z.object({ content: z.string() }) },
      },
    });

    const prompt = generateCatalogPrompt(catalog);

    expect(prompt).toContain("Validation");
    expect(prompt).toContain("required");
    expect(prompt).toContain("email");
  });
});
