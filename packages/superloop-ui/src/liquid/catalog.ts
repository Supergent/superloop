import { createCatalog } from "@json-render/core";
import { z } from "zod";

/**
 * Superloop Liquid Interface Catalog
 *
 * Defines the components available for AI-generated and default views.
 * This acts as a type system / contract for what UI can be generated.
 */
export const superloopCatalog = createCatalog({
  name: "superloop",
  components: {
    // ===================
    // Layout Components
    // ===================
    Stack: {
      props: z.object({
        direction: z
          .enum(["horizontal", "vertical"])
          .default("vertical")
          .describe("Stack direction"),
        gap: z
          .enum(["none", "sm", "md", "lg"])
          .default("md")
          .describe("Spacing between children"),
        align: z
          .enum(["start", "center", "end", "stretch"])
          .optional()
          .describe("Cross-axis alignment"),
      }),
      hasChildren: true,
      description: "Flexbox stack for arranging children horizontally or vertically",
    },

    Card: {
      props: z.object({
        title: z.string().optional().describe("Card header title"),
        subtitle: z.string().optional().describe("Card header subtitle"),
        padding: z.enum(["none", "sm", "md", "lg"]).default("md").describe("Internal padding"),
      }),
      hasChildren: true,
      description: "Container card with optional header",
    },

    Grid: {
      props: z.object({
        columns: z.number().min(1).max(4).default(2).describe("Number of columns"),
        gap: z.enum(["sm", "md", "lg"]).default("md").describe("Gap between grid items"),
      }),
      hasChildren: true,
      description: "Grid layout for arranging children in columns",
    },

    // ===================
    // Typography
    // ===================
    Heading: {
      props: z.object({
        text: z.string().describe("Heading text content"),
        level: z.enum(["h1", "h2", "h3", "h4"]).default("h2").describe("Heading level"),
      }),
      description: "Section heading with configurable level",
    },

    Text: {
      props: z.object({
        content: z.string().describe("Text content"),
        variant: z
          .enum(["body", "caption", "label", "code"])
          .default("body")
          .describe("Text style variant"),
        color: z
          .enum(["default", "muted", "success", "warning", "error"])
          .default("default")
          .describe("Text color"),
      }),
      description: "Text paragraph with style variants",
    },

    // ===================
    // Status & Feedback
    // ===================
    Badge: {
      props: z.object({
        text: z.string().describe("Badge label"),
        variant: z
          .enum(["default", "success", "warning", "error", "info"])
          .default("default")
          .describe("Badge color variant"),
      }),
      description: "Small status badge / pill",
    },

    Alert: {
      props: z.object({
        type: z.enum(["info", "success", "warning", "error"]).describe("Alert severity"),
        title: z.string().describe("Alert title"),
        message: z.string().optional().describe("Alert description"),
      }),
      description: "Alert banner for important messages",
    },

    // ===================
    // Superloop-Specific
    // ===================
    GateStatus: {
      props: z.object({
        gate: z
          .enum(["promise", "tests", "checklist", "evidence", "approval"])
          .describe("Which gate to display"),
        status: z
          .enum(["passed", "failed", "pending", "skipped"])
          .describe("Current gate status"),
        detail: z.string().optional().describe("Additional detail text"),
      }),
      description: "Displays the status of a single superloop gate",
    },

    GateSummary: {
      props: z.object({
        promise: z.enum(["passed", "failed", "pending", "skipped"]).describe("Promise gate status"),
        tests: z.enum(["passed", "failed", "pending", "skipped"]).describe("Tests gate status"),
        checklist: z
          .enum(["passed", "failed", "pending", "skipped"])
          .describe("Checklist gate status"),
        evidence: z
          .enum(["passed", "failed", "pending", "skipped"])
          .describe("Evidence gate status"),
        approval: z
          .enum(["passed", "failed", "pending", "skipped"])
          .describe("Approval gate status"),
      }),
      description: "Compact summary of all gate statuses",
    },

    IterationHeader: {
      props: z.object({
        iteration: z.number().describe("Current iteration number"),
        phase: z
          .enum(["planning", "implementing", "testing", "reviewing", "complete"])
          .optional()
          .describe("Current phase"),
        loopId: z.string().optional().describe("Loop identifier"),
      }),
      description: "Header showing current iteration and phase",
    },

    TaskList: {
      props: z.object({
        tasks: z
          .array(
            z.object({
              id: z.string(),
              title: z.string(),
              done: z.boolean(),
              level: z.number().default(0),
            }),
          )
          .describe("Array of tasks to display"),
        showCompleted: z.boolean().default(true).describe("Whether to show completed tasks"),
      }),
      description: "Hierarchical task checklist from PHASE files",
    },

    ProgressBar: {
      props: z.object({
        value: z.number().min(0).max(100).describe("Progress percentage (0-100)"),
        label: z.string().optional().describe("Progress label"),
        variant: z
          .enum(["default", "success", "warning", "error"])
          .default("default")
          .describe("Color variant"),
      }),
      description: "Visual progress indicator",
    },

    TestFailures: {
      props: z.object({
        failures: z
          .array(
            z.object({
              name: z.string(),
              message: z.string().optional(),
              file: z.string().optional(),
            }),
          )
          .describe("Array of test failures"),
      }),
      description: "List of test failures with details",
    },

    BlockerCard: {
      props: z.object({
        title: z.string().describe("Blocker title"),
        description: z.string().optional().describe("Blocker description"),
        source: z.string().optional().describe("Where the blocker was identified"),
        iteration: z.number().optional().describe("Which iteration identified this"),
      }),
      description: "Card displaying a blocker or stuck issue",
    },

    CostSummary: {
      props: z.object({
        totalUsd: z.number().describe("Total cost in USD"),
        iterations: z.number().describe("Number of iterations"),
        breakdown: z
          .array(
            z.object({
              role: z.string(),
              cost: z.number(),
            }),
          )
          .optional()
          .describe("Cost breakdown by role"),
      }),
      description: "Summary of token usage and costs",
    },

    // ===================
    // Interactive
    // ===================
    Button: {
      props: z.object({
        label: z.string().describe("Button text"),
        variant: z
          .enum(["primary", "secondary", "danger", "ghost"])
          .default("primary")
          .describe("Button style"),
        action: z.string().describe("Action name to trigger"),
        disabled: z.boolean().default(false).describe("Whether button is disabled"),
      }),
      description: "Clickable button that triggers an action",
    },

    ActionBar: {
      props: z.object({
        actions: z
          .array(
            z.object({
              label: z.string(),
              action: z.string(),
              variant: z.enum(["primary", "secondary", "danger", "ghost"]).optional(),
            }),
          )
          .describe("Array of actions to display"),
      }),
      description: "Horizontal bar of action buttons",
    },

    // ===================
    // Data Display
    // ===================
    KeyValue: {
      props: z.object({
        label: z.string().describe("Key/label text"),
        value: z.string().describe("Value text"),
      }),
      description: "Single key-value pair display",
    },

    KeyValueList: {
      props: z.object({
        items: z
          .array(
            z.object({
              label: z.string(),
              value: z.string(),
            }),
          )
          .describe("Array of key-value pairs"),
      }),
      description: "List of key-value pairs",
    },

    Divider: {
      props: z.object({
        label: z.string().optional().describe("Optional divider label"),
      }),
      description: "Visual separator between sections",
    },

    EmptyState: {
      props: z.object({
        title: z.string().describe("Empty state title"),
        message: z.string().optional().describe("Empty state description"),
        action: z.string().optional().describe("Action to suggest"),
        actionLabel: z.string().optional().describe("Action button label"),
      }),
      description: "Placeholder for empty/missing content",
    },
  },

  actions: {
    approve_loop: {
      description: "Approve the current loop iteration",
      params: z.object({
        note: z.string().optional().describe("Approval note"),
      }),
    },
    reject_loop: {
      description: "Reject the current loop iteration",
      params: z.object({
        reason: z.string().describe("Rejection reason"),
      }),
    },
    cancel_loop: {
      description: "Cancel the currently running loop",
    },
    view_artifact: {
      description: "Open an artifact file for viewing",
      params: z.object({
        path: z.string().describe("Path to the artifact"),
      }),
    },
    view_logs: {
      description: "View logs for a specific iteration",
      params: z.object({
        iteration: z.number().optional().describe("Iteration number"),
      }),
    },
    refresh: {
      description: "Refresh the dashboard data",
    },
  },

  validation: "strict",
});

export type SuperloopCatalog = typeof superloopCatalog;
