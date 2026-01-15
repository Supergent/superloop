/**
 * Liquid Interface Dashboard
 *
 * The main React component for the superloop liquid interfaces.
 * Features:
 * - Automatic default views based on loop state
 * - Override with skill-generated UITrees
 * - Live data binding with polling
 * - Action handlers for approve, cancel, etc.
 */

import { useCallback, useEffect, useState } from "react";
import { DataProvider, ActionProvider, VisibilityProvider, Renderer } from "@json-render/react";
import type { UITree, Action } from "@json-render/core";

import { superloopRegistry } from "./components/index.js";
import { selectDefaultView } from "./views/defaults.js";
import { type SuperloopContext, emptyContext } from "./views/types.js";

// ===================
// Types
// ===================

interface DashboardProps {
  /** Function to load context (injected for server/client flexibility) */
  loadContext: () => Promise<SuperloopContext>;
  /** Path to watch for UITree overrides */
  overrideTreePath?: string;
  /** Function to load override tree */
  loadOverrideTree?: () => Promise<UITree | null>;
  /** Polling interval in ms */
  pollInterval?: number;
  /** Action handlers */
  onAction?: (action: Action) => void | Promise<void>;
}

// ===================
// Dashboard Component
// ===================

export function Dashboard({
  loadContext,
  loadOverrideTree,
  pollInterval = 2000,
  onAction,
}: DashboardProps) {
  const [context, setContext] = useState<SuperloopContext>(emptyContext);
  const [overrideTree, setOverrideTree] = useState<UITree | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [lastUpdated, setLastUpdated] = useState<Date>(new Date());

  // Compute the tree to render
  const tree = overrideTree ?? selectDefaultView(context);

  // Convert context to flat data model for json-render
  const dataModel = contextToDataModel(context);

  // Poll for context updates
  useEffect(() => {
    let mounted = true;

    const poll = async () => {
      try {
        const ctx = await loadContext();
        if (mounted) {
          setContext(ctx);
          setLastUpdated(new Date());
          setError(null);
        }
      } catch (err) {
        if (mounted) {
          setError(err instanceof Error ? err.message : "Failed to load context");
        }
      }
    };

    // Initial load
    void poll();

    // Set up polling
    const interval = setInterval(poll, pollInterval);

    return () => {
      mounted = false;
      clearInterval(interval);
    };
  }, [loadContext, pollInterval]);

  // Poll for override tree
  useEffect(() => {
    if (!loadOverrideTree) return;

    let mounted = true;

    const poll = async () => {
      try {
        const tree = await loadOverrideTree();
        if (mounted) {
          setOverrideTree(tree);
        }
      } catch {
        // Ignore errors loading override
      }
    };

    void poll();
    const interval = setInterval(poll, pollInterval);

    return () => {
      mounted = false;
      clearInterval(interval);
    };
  }, [loadOverrideTree, pollInterval]);

  // Action handler
  const handleAction = useCallback(
    async (action: Action) => {
      console.log("Action triggered:", action);

      // Handle built-in actions
      switch (action.name) {
        case "refresh":
          try {
            const ctx = await loadContext();
            setContext(ctx);
            setLastUpdated(new Date());
          } catch (err) {
            setError(err instanceof Error ? err.message : "Refresh failed");
          }
          return;

        case "clear_override":
          setOverrideTree(null);
          return;
      }

      // Delegate to external handler
      if (onAction) {
        await onAction(action);
      }
    },
    [loadContext, onAction],
  );

  return (
    <div
      style={{
        minHeight: "100vh",
        background: "#0a0a0a",
        color: "#fafafa",
        fontFamily:
          '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif',
      }}
    >
      <div style={{ maxWidth: 960, margin: "0 auto", padding: "32px 24px" }}>
        {/* Header */}
        <header style={{ marginBottom: 32 }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
            <div>
              <h1
                style={{
                  margin: 0,
                  fontSize: 24,
                  fontWeight: 600,
                  letterSpacing: "-0.02em",
                }}
              >
                Superloop Dashboard
              </h1>
              <p style={{ margin: "4px 0 0", fontSize: 14, color: "#a1a1aa" }}>
                {context.loopId ? `Loop: ${context.loopId}` : "Liquid Interface"}
              </p>
            </div>
            <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
              {overrideTree && (
                <button
                  type="button"
                  onClick={() => setOverrideTree(null)}
                  style={{
                    padding: "6px 12px",
                    fontSize: 13,
                    background: "#262626",
                    color: "#a1a1aa",
                    border: "none",
                    borderRadius: 6,
                    cursor: "pointer",
                  }}
                >
                  Clear Override
                </button>
              )}
              <span style={{ fontSize: 12, color: "#71717a" }}>
                Updated {lastUpdated.toLocaleTimeString()}
              </span>
            </div>
          </div>
        </header>

        {/* Error Banner */}
        {error && (
          <div
            style={{
              padding: 16,
              marginBottom: 24,
              background: "#450a0a",
              border: "1px solid #ef4444",
              borderRadius: 8,
              color: "#fecaca",
            }}
          >
            {error}
          </div>
        )}

        {/* Override Indicator */}
        {overrideTree && (
          <div
            style={{
              padding: "8px 16px",
              marginBottom: 16,
              background: "#1e3a5f",
              borderRadius: 6,
              fontSize: 13,
              display: "flex",
              alignItems: "center",
              gap: 8,
            }}
          >
            <span style={{ color: "#3b82f6" }}>●</span>
            <span>Showing custom view from /superloop-view skill</span>
          </div>
        )}

        {/* Main Content */}
        <DataProvider initialData={dataModel}>
          <VisibilityProvider>
            <ActionProvider handlers={{}} onExecute={handleAction}>
              <Renderer tree={tree} registry={superloopRegistry} />
            </ActionProvider>
          </VisibilityProvider>
        </DataProvider>
      </div>
    </div>
  );
}

// ===================
// Helpers
// ===================

/**
 * Convert SuperloopContext to a flat data model for json-render data binding
 */
function contextToDataModel(ctx: SuperloopContext): Record<string, unknown> {
  return {
    loop: {
      id: ctx.loopId,
      active: ctx.active,
      iteration: ctx.iteration,
      phase: ctx.phase,
    },
    gates: ctx.gates,
    tasks: ctx.tasks,
    taskProgress: ctx.taskProgress,
    testFailures: ctx.testFailures,
    blockers: ctx.blockers,
    stuck: ctx.stuck,
    stuckIterations: ctx.stuckIterations,
    cost: ctx.cost,
    startedAt: ctx.startedAt,
    endedAt: ctx.endedAt,
    updatedAt: ctx.updatedAt,
    completionOk: ctx.completionOk,
    iterations: ctx.iterations,
  };
}

// ===================
// Export
// ===================

export { type SuperloopContext } from "./views/types.js";
export { loadSuperloopContext } from "./context-loader.js";
export { selectDefaultView } from "./views/defaults.js";
export { superloopCatalog } from "./catalog.js";
export { superloopRegistry } from "./components/index.js";
