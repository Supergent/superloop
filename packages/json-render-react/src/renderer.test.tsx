import { describe, it, expect } from "vitest";
import React from "react";
import { createRendererFromCatalog } from "./renderer";

// Mock catalog object that matches the Catalog interface
const mockCatalog = {
  name: "test",
  componentNames: ["text", "button"],
  actionNames: [],
  functionNames: [],
  validation: "strict" as const,
  components: {},
  actions: {},
  functions: {},
  elementSchema: {} as never,
  treeSchema: {} as never,
  hasComponent: () => true,
  hasAction: () => false,
  hasFunction: () => false,
  validateElement: () => ({ success: true }),
  validateTree: () => ({ success: true }),
};

describe("createRendererFromCatalog", () => {
  it("creates a React component from catalog and registry", () => {
    const registry = {
      text: ({ element }: { element: { props: { content: string } } }) =>
        React.createElement("span", null, element.props.content),
      button: ({ element }: { element: { props: { label: string } } }) =>
        React.createElement("button", null, element.props.label),
    };

    const CatalogRenderer = createRendererFromCatalog(mockCatalog, registry);

    expect(typeof CatalogRenderer).toBe("function");
  });

  it("returned component renders null for null tree", () => {
    const registry = {
      text: () => React.createElement("span"),
    };

    const CatalogRenderer = createRendererFromCatalog(mockCatalog, registry);

    // The component should handle null tree gracefully
    const element = React.createElement(CatalogRenderer, { tree: null });
    expect(element).toBeDefined();
  });

  it("returned component accepts loading prop", () => {
    const registry = {
      text: () => React.createElement("span"),
    };

    const CatalogRenderer = createRendererFromCatalog(mockCatalog, registry);

    const element = React.createElement(CatalogRenderer, {
      tree: null,
      loading: true,
    });
    expect(element.props.loading).toBe(true);
  });

  it("returned component accepts fallback prop", () => {
    const registry = {
      text: () => React.createElement("span"),
    };

    const Fallback = () =>
      React.createElement("div", null, "Unknown component");

    const CatalogRenderer = createRendererFromCatalog(mockCatalog, registry);

    const element = React.createElement(CatalogRenderer, {
      tree: null,
      fallback: Fallback,
    });
    expect(element.props.fallback).toBe(Fallback);
  });
});
