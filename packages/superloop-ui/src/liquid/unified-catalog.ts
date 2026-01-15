/**
 * Unified Liquid Interface Catalog
 *
 * Merges the Superloop-specific components with Tool UI components
 * to provide a comprehensive component library for AI-generated dashboards.
 */

import { createCatalog } from "@json-render/core";
import { superloopCatalog } from "./catalog.js";
import { toolUICatalog } from "./tool-ui-catalog.js";

/**
 * Unified catalog combining Superloop and Tool UI components.
 *
 * Component categories:
 * - Layout: Stack, Card, Grid
 * - Typography: Heading, Text
 * - Status: Badge, Alert, GateStatus, GateSummary
 * - Superloop: IterationHeader, TaskList, ProgressBar, TestFailures, BlockerCard, CostSummary
 * - Interactive: Button, ActionBar
 * - Data: KeyValue, KeyValueList, Divider, EmptyState
 * - Tool UI: CodeBlock, Terminal, ApprovalCard, Image, DataTable, OptionList, etc.
 */
export const unifiedCatalog = createCatalog({
  name: "superloop-unified",

  // Merge component definitions
  components: {
    ...superloopCatalog.components,
    ...toolUICatalog.components,
  },

  // Merge action definitions
  actions: {
    ...superloopCatalog.actions,
    ...toolUICatalog.actions,
  },

  validation: "strict",
});

export type UnifiedCatalog = typeof unifiedCatalog;

/**
 * Check if a component type exists in the unified catalog
 */
export function hasComponent(type: string): boolean {
  return type in unifiedCatalog.components;
}

/**
 * Get all available component types
 */
export function getComponentTypes(): string[] {
  return Object.keys(unifiedCatalog.components);
}

/**
 * Get all available action types
 */
export function getActionTypes(): string[] {
  return Object.keys(unifiedCatalog.actions);
}

// Re-export individual catalogs for cases where only one is needed
export { superloopCatalog } from "./catalog.js";
export { toolUICatalog } from "./tool-ui-catalog.js";
