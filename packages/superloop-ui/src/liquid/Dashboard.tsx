/**
 * Liquid Interface Dashboard
 *
 * The main React component for the superloop liquid interfaces.
 * Features:
 * - Automatic default views based on loop state
 * - Override with skill-generated UITrees
 * - Versioned view history (high-fidelity prototyping)
 * - Live data binding with polling
 * - Action handlers for approve, cancel, etc.
 */

import { useCallback, useEffect, useMemo, useState } from "react";
import { DataProvider, ActionProvider, VisibilityProvider, Renderer } from "@json-render/react";
import type { UITree, Action } from "@json-render/core";

import { superloopRegistry, unifiedRegistry } from "./components/index.js";
import { selectDefaultView } from "./views/defaults.js";
import { type SuperloopContext, emptyContext } from "./views/types.js";
import type { LiquidView, ViewVersion } from "./storage.js";

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
  /** Function to load versioned view */
  loadVersionedView?: () => Promise<LiquidView | null>;
  /** Callback when version is selected */
  onVersionSelect?: (versionId: string | null) => void | Promise<void>;
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
  loadVersionedView,
  onVersionSelect,
  pollInterval = 2000,
  onAction,
}: DashboardProps) {
  const [context, setContext] = useState<SuperloopContext>(emptyContext);
  const [overrideTree, setOverrideTree] = useState<UITree | null>(null);
  const [versionedView, setVersionedView] = useState<LiquidView | null>(null);
  const [selectedVersionId, setSelectedVersionId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [lastUpdated, setLastUpdated] = useState<Date>(new Date());

  // Compute the tree to render (priority: selected version > override > versioned active > default)
  const tree = (() => {
    // If a specific version is selected from history
    if (selectedVersionId && versionedView) {
      const version = versionedView.versions.find((v) => v.id === selectedVersionId);
      if (version) return version.tree;
    }
    // If there's an override (from skill)
    if (overrideTree) return overrideTree;
    // If there's a versioned view with an active version
    if (versionedView) return versionedView.active.tree;
    // Fall back to default view based on context
    return selectDefaultView(context);
  })();

  // Get current version info for display
  const currentVersion: ViewVersion | null = (() => {
    if (selectedVersionId && versionedView) {
      return versionedView.versions.find((v) => v.id === selectedVersionId) ?? null;
    }
    if (versionedView) {
      return versionedView.active;
    }
    return null;
  })();

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

  // Poll for versioned view
  useEffect(() => {
    if (!loadVersionedView) return;

    let mounted = true;

    const poll = async () => {
      try {
        const view = await loadVersionedView();
        if (mounted) {
          setVersionedView(view);
        }
      } catch {
        // Ignore errors loading versioned view
      }
    };

    void poll();
    const interval = setInterval(poll, pollInterval);

    return () => {
      mounted = false;
      clearInterval(interval);
    };
  }, [loadVersionedView, pollInterval]);

  // Handle version selection
  const handleVersionSelect = useCallback(
    async (versionId: string | null) => {
      setSelectedVersionId(versionId);
      if (onVersionSelect) {
        await onVersionSelect(versionId);
      }
    },
    [onVersionSelect],
  );

  // Build action handlers record for ActionProvider
  const actionHandlers = useMemo(() => {
    const handlers: Record<string, () => Promise<void> | void> = {
      refresh: async () => {
        try {
          const ctx = await loadContext();
          setContext(ctx);
          setLastUpdated(new Date());
        } catch (err) {
          setError(err instanceof Error ? err.message : "Refresh failed");
        }
      },
      clear_override: () => {
        setOverrideTree(null);
      },
    };

    // Add external action handlers
    if (onAction) {
      // Wrap external handler for common actions
      const externalActions = [
        "approve_loop",
        "reject_loop",
        "cancel_loop",
        "view_artifact",
        "view_logs",
      ];
      for (const name of externalActions) {
        handlers[name] = async () => {
          await onAction({ name });
        };
      }
    }

    return handlers;
  }, [loadContext, onAction]);

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

        {/* Version Selector */}
        {versionedView && versionedView.versions.length > 1 && (
          <VersionSelector
            view={versionedView}
            selectedVersionId={selectedVersionId}
            onSelect={handleVersionSelect}
          />
        )}

        {/* Version Info Banner */}
        {currentVersion && !overrideTree && (
          <div
            style={{
              padding: "8px 16px",
              marginBottom: 16,
              background: "#1a1a2e",
              borderRadius: 6,
              fontSize: 13,
              display: "flex",
              alignItems: "center",
              justifyContent: "space-between",
            }}
          >
            <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
              <span style={{ color: "#8b5cf6" }}>●</span>
              <span>
                {versionedView?.name ?? "Custom View"} — v{currentVersion.id}
              </span>
              {currentVersion.prompt && (
                <span style={{ color: "#71717a", marginLeft: 8 }}>
                  "{currentVersion.prompt.slice(0, 50)}
                  {currentVersion.prompt.length > 50 ? "..." : ""}"
                </span>
              )}
            </div>
            {selectedVersionId && (
              <button
                type="button"
                onClick={() => handleVersionSelect(null)}
                style={{
                  padding: "4px 8px",
                  fontSize: 12,
                  background: "#262626",
                  color: "#a1a1aa",
                  border: "none",
                  borderRadius: 4,
                  cursor: "pointer",
                }}
              >
                Use Latest
              </button>
            )}
          </div>
        )}

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
            <ActionProvider handlers={actionHandlers}>
              <Renderer tree={tree} registry={unifiedRegistry} />
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
// Version Selector Component
// ===================

interface VersionSelectorProps {
  view: LiquidView;
  selectedVersionId: string | null;
  onSelect: (versionId: string | null) => void;
}

function VersionSelector({ view, selectedVersionId, onSelect }: VersionSelectorProps) {
  const versions = view.versions;
  const activeIndex = selectedVersionId
    ? versions.findIndex((v) => v.id === selectedVersionId)
    : versions.length - 1;

  return (
    <div
      style={{
        marginBottom: 24,
        padding: 16,
        background: "#18181b",
        borderRadius: 8,
        border: "1px solid #27272a",
      }}
    >
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
          marginBottom: 12,
        }}
      >
        <span style={{ fontSize: 13, fontWeight: 500, color: "#a1a1aa" }}>
          Version History ({versions.length} versions)
        </span>
        <span style={{ fontSize: 12, color: "#71717a" }}>{view.name}</span>
      </div>

      {/* Version Timeline */}
      <div style={{ display: "flex", alignItems: "center", gap: 4 }}>
        {versions.map((version, index) => {
          const isActive = index === activeIndex;
          const isLatest = index === versions.length - 1;

          return (
            <button
              key={version.id}
              type="button"
              onClick={() => onSelect(isLatest ? null : version.id)}
              title={`${version.id}${version.prompt ? `: ${version.prompt}` : ""}`}
              style={{
                flex: 1,
                height: 8,
                background: isActive ? "#8b5cf6" : "#3f3f46",
                border: "none",
                borderRadius: 2,
                cursor: "pointer",
                transition: "background 0.15s",
              }}
              onMouseEnter={(e) => {
                if (!isActive) e.currentTarget.style.background = "#52525b";
              }}
              onMouseLeave={(e) => {
                if (!isActive) e.currentTarget.style.background = "#3f3f46";
              }}
            />
          );
        })}
      </div>

      {/* Version Labels */}
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          marginTop: 8,
          fontSize: 11,
          color: "#71717a",
        }}
      >
        <span>v1</span>
        <span>v{versions.length} (latest)</span>
      </div>
    </div>
  );
}

// ===================
// Export
// ===================

export { type SuperloopContext } from "./views/types.js";
export { loadSuperloopContext } from "./context-loader.js";
export { selectDefaultView } from "./views/defaults.js";
export { superloopCatalog } from "./catalog.js";
export { toolUICatalog } from "./tool-ui-catalog.js";
export { unifiedCatalog } from "./unified-catalog.js";
export { superloopRegistry, unifiedRegistry } from "./components/index.js";
export { toolUIRegistry } from "./tool-ui/index.js";
export type { LiquidView, ViewVersion } from "./storage.js";
export {
  listViews,
  loadView,
  loadActiveTree,
  saveVersion,
  setActiveVersion,
  loadVersion,
  deleteVersion,
  deleteView,
} from "./storage.js";
