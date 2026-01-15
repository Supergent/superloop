/**
 * Default Views
 *
 * These are pre-built UITrees for common superloop states.
 * The dashboard automatically selects the appropriate view based on current state.
 * No AI needed - instant, free, predictable.
 */

import type { UITree } from "@json-render/core";
import type { SuperloopContext, GateStatusValue } from "./types.js";

/**
 * Select the appropriate default view based on current context
 */
export function selectDefaultView(ctx: SuperloopContext): UITree {
  // No active loop
  if (!ctx.active || !ctx.loopId) {
    return idleView(ctx);
  }

  // Loop is complete
  if (ctx.completionOk) {
    return completeView(ctx);
  }

  // Stuck - multiple iterations without progress
  if (ctx.stuck) {
    return stuckView(ctx);
  }

  // Tests failing
  if (ctx.gates.tests === "failed") {
    return testFailureView(ctx);
  }

  // Awaiting approval
  if (ctx.gates.approval === "pending" && ctx.gates.promise === "passed") {
    return approvalView(ctx);
  }

  // Default: show progress
  return progressView(ctx);
}

// ===================
// View Builders
// ===================

/**
 * No active loop - show idle state
 */
function idleView(_ctx: SuperloopContext): UITree {
  return {
    root: "root",
    elements: {
      root: {
        key: "root",
        type: "Card",
        props: { padding: "lg" },
        children: ["empty"],
      },
      empty: {
        key: "empty",
        type: "EmptyState",
        props: {
          title: "No Active Loop",
          message: "Start a superloop to see status here",
          action: "refresh",
          actionLabel: "Refresh",
        },
      },
    },
  };
}

/**
 * Loop completed successfully
 */
function completeView(ctx: SuperloopContext): UITree {
  return {
    root: "root",
    elements: {
      root: {
        key: "root",
        type: "Stack",
        props: { gap: "lg" },
        children: ["header", "alert", "summary", "cost"],
      },
      header: {
        key: "header",
        type: "IterationHeader",
        props: {
          iteration: ctx.iteration,
          phase: "complete",
          loopId: ctx.loopId,
        },
      },
      alert: {
        key: "alert",
        type: "Alert",
        props: {
          type: "success",
          title: "Loop Complete",
          message: `Successfully completed in ${ctx.iteration} iteration${ctx.iteration !== 1 ? "s" : ""}`,
        },
      },
      summary: {
        key: "summary",
        type: "Card",
        props: { title: "Final Gate Status" },
        children: ["gates"],
      },
      gates: {
        key: "gates",
        type: "GateSummary",
        props: ctx.gates,
      },
      cost: {
        key: "cost",
        type: "Card",
        props: { title: "Cost Summary" },
        children: ["cost-details"],
      },
      "cost-details": {
        key: "cost-details",
        type: "CostSummary",
        props: {
          totalUsd: ctx.cost.totalUsd,
          iterations: ctx.cost.iterations,
          breakdown: ctx.cost.breakdown,
        },
      },
    },
  };
}

/**
 * Loop is stuck - multiple iterations without progress
 */
function stuckView(ctx: SuperloopContext): UITree {
  const elements: UITree["elements"] = {
    root: {
      key: "root",
      type: "Stack",
      props: { gap: "lg" },
      children: ["header", "alert", "gates-card", "blockers-card"],
    },
    header: {
      key: "header",
      type: "IterationHeader",
      props: {
        iteration: ctx.iteration,
        phase: ctx.phase,
        loopId: ctx.loopId,
      },
    },
    alert: {
      key: "alert",
      type: "Alert",
      props: {
        type: "warning",
        title: "Loop May Be Stuck",
        message: `${ctx.stuckIterations} iterations without progress. Review blockers below.`,
      },
    },
    "gates-card": {
      key: "gates-card",
      type: "Card",
      props: { title: "Gate Status" },
      children: ["gates"],
    },
    gates: {
      key: "gates",
      type: "GateSummary",
      props: ctx.gates,
    },
    "blockers-card": {
      key: "blockers-card",
      type: "Card",
      props: { title: "Potential Blockers" },
      children: ctx.blockers.length > 0 ? ["blockers"] : ["no-blockers"],
    },
  };

  if (ctx.blockers.length > 0) {
    elements.blockers = {
      key: "blockers",
      type: "Stack",
      props: { gap: "sm" },
      children: ctx.blockers.map((_, i) => `blocker-${i}`),
    };
    ctx.blockers.forEach((blocker, i) => {
      elements[`blocker-${i}`] = {
        key: `blocker-${i}`,
        type: "BlockerCard",
        props: blocker,
      };
    });
  } else {
    elements["no-blockers"] = {
      key: "no-blockers",
      type: "Text",
      props: {
        content: "No specific blockers identified. Check logs for details.",
        color: "muted",
      },
    };
  }

  // Add actions
  elements.root.children?.push("actions");
  elements.actions = {
    key: "actions",
    type: "ActionBar",
    props: {
      actions: [
        { label: "View Logs", action: "view_logs" },
        { label: "Cancel Loop", action: "cancel_loop", variant: "danger" },
      ],
    },
  };

  return { root: "root", elements };
}

/**
 * Tests are failing
 */
function testFailureView(ctx: SuperloopContext): UITree {
  const elements: UITree["elements"] = {
    root: {
      key: "root",
      type: "Stack",
      props: { gap: "lg" },
      children: ["header", "alert", "failures-card", "gates-card"],
    },
    header: {
      key: "header",
      type: "IterationHeader",
      props: {
        iteration: ctx.iteration,
        phase: "testing",
        loopId: ctx.loopId,
      },
    },
    alert: {
      key: "alert",
      type: "Alert",
      props: {
        type: "error",
        title: "Tests Failing",
        message: `${ctx.testFailures.length} test${ctx.testFailures.length !== 1 ? "s" : ""} failing`,
      },
    },
    "failures-card": {
      key: "failures-card",
      type: "Card",
      props: { title: "Test Failures" },
      children: ["failures"],
    },
    failures: {
      key: "failures",
      type: "TestFailures",
      props: { failures: ctx.testFailures },
    },
    "gates-card": {
      key: "gates-card",
      type: "Card",
      props: { title: "Gate Status" },
      children: ["gates"],
    },
    gates: {
      key: "gates",
      type: "GateSummary",
      props: ctx.gates,
    },
  };

  return { root: "root", elements };
}

/**
 * Awaiting human approval
 */
function approvalView(ctx: SuperloopContext): UITree {
  return {
    root: "root",
    elements: {
      root: {
        key: "root",
        type: "Stack",
        props: { gap: "lg" },
        children: ["header", "alert", "gates-card", "progress-card", "actions"],
      },
      header: {
        key: "header",
        type: "IterationHeader",
        props: {
          iteration: ctx.iteration,
          phase: "reviewing",
          loopId: ctx.loopId,
        },
      },
      alert: {
        key: "alert",
        type: "Alert",
        props: {
          type: "info",
          title: "Awaiting Approval",
          message: "All gates passed. Human approval required to complete.",
        },
      },
      "gates-card": {
        key: "gates-card",
        type: "Card",
        props: { title: "Gate Status" },
        children: ["gates"],
      },
      gates: {
        key: "gates",
        type: "GateSummary",
        props: ctx.gates,
      },
      "progress-card": {
        key: "progress-card",
        type: "Card",
        props: { title: "Task Progress" },
        children: ["progress", "tasks"],
      },
      progress: {
        key: "progress",
        type: "ProgressBar",
        props: {
          value: ctx.taskProgress.percent,
          label: `${ctx.taskProgress.completed}/${ctx.taskProgress.total} tasks`,
          variant: "success",
        },
      },
      tasks: {
        key: "tasks",
        type: "TaskList",
        props: { tasks: ctx.tasks, showCompleted: true },
      },
      actions: {
        key: "actions",
        type: "ActionBar",
        props: {
          actions: [
            { label: "Approve", action: "approve_loop", variant: "primary" },
            { label: "Reject", action: "reject_loop", variant: "danger" },
            { label: "View Artifacts", action: "view_artifact" },
          ],
        },
      },
    },
  };
}

/**
 * Default progress view - loop is running normally
 */
function progressView(ctx: SuperloopContext): UITree {
  const children = ["header", "gates-card", "progress-card"];

  const elements: UITree["elements"] = {
    root: {
      key: "root",
      type: "Stack",
      props: { gap: "lg" },
      children,
    },
    header: {
      key: "header",
      type: "IterationHeader",
      props: {
        iteration: ctx.iteration,
        phase: ctx.phase,
        loopId: ctx.loopId,
      },
    },
    "gates-card": {
      key: "gates-card",
      type: "Card",
      props: { title: "Gate Status" },
      children: ["gates"],
    },
    gates: {
      key: "gates",
      type: "GateSummary",
      props: ctx.gates,
    },
    "progress-card": {
      key: "progress-card",
      type: "Card",
      props: { title: "Task Progress" },
      children: ["progress", "tasks"],
    },
    progress: {
      key: "progress",
      type: "ProgressBar",
      props: {
        value: ctx.taskProgress.percent,
        label: `${ctx.taskProgress.completed}/${ctx.taskProgress.total} tasks`,
        variant: ctx.taskProgress.percent === 100 ? "success" : "default",
      },
    },
    tasks: {
      key: "tasks",
      type: "TaskList",
      props: { tasks: ctx.tasks.slice(0, 10), showCompleted: true },
    },
  };

  // Add info section
  children.push("info-card");
  elements["info-card"] = {
    key: "info-card",
    type: "Card",
    props: { title: "Loop Info" },
    children: ["info"],
  };
  elements.info = {
    key: "info",
    type: "KeyValueList",
    props: {
      items: [
        { label: "Loop ID", value: ctx.loopId || "—" },
        { label: "Started", value: ctx.startedAt ? new Date(ctx.startedAt).toLocaleString() : "—" },
        { label: "Updated", value: new Date(ctx.updatedAt).toLocaleString() },
      ],
    },
  };

  return { root: "root", elements };
}

/**
 * Helper to normalize gate status from string
 */
export function normalizeGateStatus(status: string | undefined): GateStatusValue {
  switch (status?.toLowerCase()) {
    case "passed":
    case "ok":
    case "pass":
    case "true":
      return "passed";
    case "failed":
    case "fail":
    case "false":
    case "error":
      return "failed";
    case "skipped":
    case "skip":
      return "skipped";
    default:
      return "pending";
  }
}
