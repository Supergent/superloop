/**
 * Superloop Liquid Interfaces
 *
 * AI-generated and automatic contextual dashboards for superloop.
 */

// Main dashboard component
export { Dashboard, type SuperloopContext } from "./Dashboard.js";

// Context loading
export { loadSuperloopContext } from "./context-loader.js";

// Catalog and registry
export { superloopCatalog } from "./catalog.js";
export { superloopRegistry } from "./components/index.js";

// Default views
export { selectDefaultView } from "./views/defaults.js";
export { emptyContext } from "./views/types.js";
export type {
  GateStatusValue,
  GatesState,
  LoopPhase,
  TaskItem,
  TestFailure,
  Blocker,
  CostByRole,
  IterationSummary,
} from "./views/types.js";
