/**
 * Superloop Liquid Interface Component Registry
 *
 * React implementations for each component in the catalog.
 * These render the actual UI from UITree elements.
 */

import type { ComponentRenderProps } from "@json-render/react";
import type { ReactNode } from "react";

// ===================
// Styles (inline for simplicity, can extract later)
// ===================

const colors = {
  bg: "#0a0a0a",
  card: "#141414",
  border: "#262626",
  text: "#fafafa",
  muted: "#a1a1aa",
  success: "#22c55e",
  warning: "#eab308",
  error: "#ef4444",
  info: "#3b82f6",
};

const spacing = {
  none: "0",
  sm: "8px",
  md: "16px",
  lg: "24px",
};

// ===================
// Layout Components
// ===================

export function Stack({ element, children }: ComponentRenderProps) {
  const props = element.props as {
    direction?: "horizontal" | "vertical";
    gap?: "none" | "sm" | "md" | "lg";
    align?: "start" | "center" | "end" | "stretch";
  };

  return (
    <div
      style={{
        display: "flex",
        flexDirection: props.direction === "horizontal" ? "row" : "column",
        gap: spacing[props.gap || "md"],
        alignItems: props.align || "stretch",
      }}
    >
      {children}
    </div>
  );
}

export function Card({ element, children }: ComponentRenderProps) {
  const props = element.props as {
    title?: string;
    subtitle?: string;
    padding?: "none" | "sm" | "md" | "lg";
  };

  return (
    <div
      style={{
        background: colors.card,
        border: `1px solid ${colors.border}`,
        borderRadius: "8px",
        padding: spacing[props.padding || "md"],
      }}
    >
      {(props.title || props.subtitle) && (
        <div style={{ marginBottom: spacing.md }}>
          {props.title && (
            <h3 style={{ margin: 0, fontSize: "16px", fontWeight: 600 }}>{props.title}</h3>
          )}
          {props.subtitle && (
            <p style={{ margin: "4px 0 0", fontSize: "14px", color: colors.muted }}>
              {props.subtitle}
            </p>
          )}
        </div>
      )}
      {children}
    </div>
  );
}

export function Grid({ element, children }: ComponentRenderProps) {
  const props = element.props as {
    columns?: number;
    gap?: "sm" | "md" | "lg";
  };

  return (
    <div
      style={{
        display: "grid",
        gridTemplateColumns: `repeat(${props.columns || 2}, 1fr)`,
        gap: spacing[props.gap || "md"],
      }}
    >
      {children}
    </div>
  );
}

// ===================
// Typography
// ===================

export function Heading({ element }: ComponentRenderProps) {
  const props = element.props as {
    text: string;
    level?: "h1" | "h2" | "h3" | "h4";
  };

  const sizes = { h1: "28px", h2: "22px", h3: "18px", h4: "16px" };
  const Tag = props.level || "h2";

  return (
    <Tag
      style={{
        margin: 0,
        fontSize: sizes[props.level || "h2"],
        fontWeight: 600,
        letterSpacing: "-0.02em",
      }}
    >
      {props.text}
    </Tag>
  );
}

export function Text({ element }: ComponentRenderProps) {
  const props = element.props as {
    content: string;
    variant?: "body" | "caption" | "label" | "code";
    color?: "default" | "muted" | "success" | "warning" | "error";
  };

  const variantStyles: Record<string, React.CSSProperties> = {
    body: { fontSize: "14px" },
    caption: { fontSize: "12px", color: colors.muted },
    label: { fontSize: "12px", fontWeight: 500, textTransform: "uppercase", letterSpacing: "0.05em" },
    code: { fontSize: "13px", fontFamily: "monospace", background: colors.border, padding: "2px 6px", borderRadius: "4px" },
  };

  const colorMap = {
    default: colors.text,
    muted: colors.muted,
    success: colors.success,
    warning: colors.warning,
    error: colors.error,
  };

  return (
    <p
      style={{
        margin: 0,
        color: colorMap[props.color || "default"],
        ...variantStyles[props.variant || "body"],
      }}
    >
      {props.content}
    </p>
  );
}

// ===================
// Status & Feedback
// ===================

export function Badge({ element }: ComponentRenderProps) {
  const props = element.props as {
    text: string;
    variant?: "default" | "success" | "warning" | "error" | "info";
  };

  const variantColors = {
    default: { bg: colors.border, text: colors.text },
    success: { bg: "#166534", text: "#bbf7d0" },
    warning: { bg: "#854d0e", text: "#fef08a" },
    error: { bg: "#991b1b", text: "#fecaca" },
    info: { bg: "#1e40af", text: "#bfdbfe" },
  };

  const variant = props.variant || "default";

  return (
    <span
      style={{
        display: "inline-block",
        padding: "2px 8px",
        fontSize: "12px",
        fontWeight: 500,
        borderRadius: "9999px",
        background: variantColors[variant].bg,
        color: variantColors[variant].text,
      }}
    >
      {props.text}
    </span>
  );
}

export function Alert({ element }: ComponentRenderProps) {
  const props = element.props as {
    type: "info" | "success" | "warning" | "error";
    title: string;
    message?: string;
  };

  const typeStyles = {
    info: { border: colors.info, bg: "#1e3a5f" },
    success: { border: colors.success, bg: "#14532d" },
    warning: { border: colors.warning, bg: "#422006" },
    error: { border: colors.error, bg: "#450a0a" },
  };

  const style = typeStyles[props.type];

  return (
    <div
      style={{
        padding: spacing.md,
        borderLeft: `4px solid ${style.border}`,
        background: style.bg,
        borderRadius: "4px",
      }}
    >
      <strong style={{ display: "block", marginBottom: props.message ? "4px" : 0 }}>
        {props.title}
      </strong>
      {props.message && (
        <span style={{ fontSize: "14px", color: colors.muted }}>{props.message}</span>
      )}
    </div>
  );
}

// ===================
// Superloop-Specific
// ===================

export function GateStatus({ element }: ComponentRenderProps) {
  const props = element.props as {
    gate: "promise" | "tests" | "checklist" | "evidence" | "approval";
    status: "passed" | "failed" | "pending" | "skipped";
    detail?: string;
  };

  const statusIcons = {
    passed: "✓",
    failed: "✗",
    pending: "○",
    skipped: "–",
  };

  const statusColors = {
    passed: colors.success,
    failed: colors.error,
    pending: colors.warning,
    skipped: colors.muted,
  };

  const gateLabels = {
    promise: "Promise",
    tests: "Tests",
    checklist: "Checklist",
    evidence: "Evidence",
    approval: "Approval",
  };

  return (
    <div style={{ display: "flex", alignItems: "center", gap: spacing.sm }}>
      <span
        style={{
          color: statusColors[props.status],
          fontSize: "16px",
          fontWeight: 600,
          width: "20px",
        }}
      >
        {statusIcons[props.status]}
      </span>
      <span style={{ fontWeight: 500 }}>{gateLabels[props.gate]}</span>
      {props.detail && (
        <span style={{ color: colors.muted, fontSize: "13px" }}>({props.detail})</span>
      )}
    </div>
  );
}

export function GateSummary({ element }: ComponentRenderProps) {
  const props = element.props as {
    promise: "passed" | "failed" | "pending" | "skipped";
    tests: "passed" | "failed" | "pending" | "skipped";
    checklist: "passed" | "failed" | "pending" | "skipped";
    evidence: "passed" | "failed" | "pending" | "skipped";
    approval: "passed" | "failed" | "pending" | "skipped";
  };

  const gates = ["promise", "tests", "checklist", "evidence", "approval"] as const;

  return (
    <div style={{ display: "flex", gap: spacing.md, flexWrap: "wrap" }}>
      {gates.map((gate) => (
        <GateStatus
          key={gate}
          element={{
            ...element,
            props: { gate, status: props[gate] },
          }}
        />
      ))}
    </div>
  );
}

export function IterationHeader({ element }: ComponentRenderProps) {
  const props = element.props as {
    iteration: number;
    phase?: "planning" | "implementing" | "testing" | "reviewing" | "complete";
    loopId?: string;
  };

  const phaseLabels = {
    planning: "Planning",
    implementing: "Implementing",
    testing: "Testing",
    reviewing: "Reviewing",
    complete: "Complete",
  };

  return (
    <div style={{ display: "flex", alignItems: "baseline", gap: spacing.md }}>
      <span style={{ fontSize: "28px", fontWeight: 700 }}>Iteration {props.iteration}</span>
      {props.phase && (
        <Badge
          element={{
            ...element,
            props: {
              text: phaseLabels[props.phase],
              variant: props.phase === "complete" ? "success" : "info",
            },
          }}
        />
      )}
      {props.loopId && (
        <span style={{ color: colors.muted, fontSize: "14px" }}>{props.loopId}</span>
      )}
    </div>
  );
}

export function TaskList({ element }: ComponentRenderProps) {
  const props = element.props as {
    tasks: Array<{ id: string; title: string; done: boolean; level?: number }>;
    showCompleted?: boolean;
  };

  const tasks = props.showCompleted === false ? props.tasks.filter((t) => !t.done) : props.tasks;

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "4px" }}>
      {tasks.map((task) => (
        <div
          key={task.id}
          style={{
            display: "flex",
            alignItems: "center",
            gap: spacing.sm,
            paddingLeft: `${(task.level || 0) * 16}px`,
            opacity: task.done ? 0.6 : 1,
          }}
        >
          <span style={{ color: task.done ? colors.success : colors.muted }}>
            {task.done ? "☑" : "☐"}
          </span>
          <span style={{ textDecoration: task.done ? "line-through" : "none" }}>{task.title}</span>
        </div>
      ))}
    </div>
  );
}

export function ProgressBar({ element }: ComponentRenderProps) {
  const props = element.props as {
    value: number;
    label?: string;
    variant?: "default" | "success" | "warning" | "error";
  };

  const variantColors = {
    default: colors.info,
    success: colors.success,
    warning: colors.warning,
    error: colors.error,
  };

  return (
    <div>
      {props.label && (
        <div style={{ display: "flex", justifyContent: "space-between", marginBottom: "4px" }}>
          <span style={{ fontSize: "13px" }}>{props.label}</span>
          <span style={{ fontSize: "13px", color: colors.muted }}>{props.value}%</span>
        </div>
      )}
      <div
        style={{
          height: "8px",
          background: colors.border,
          borderRadius: "4px",
          overflow: "hidden",
        }}
      >
        <div
          style={{
            height: "100%",
            width: `${props.value}%`,
            background: variantColors[props.variant || "default"],
            borderRadius: "4px",
            transition: "width 0.3s ease",
          }}
        />
      </div>
    </div>
  );
}

export function TestFailures({ element }: ComponentRenderProps) {
  const props = element.props as {
    failures: Array<{ name: string; message?: string; file?: string }>;
  };

  if (props.failures.length === 0) {
    return (
      <Text
        element={{
          ...element,
          props: { content: "No test failures", color: "muted" },
        }}
      />
    );
  }

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: spacing.sm }}>
      {props.failures.map((failure, i) => (
        <div
          key={i}
          style={{
            padding: spacing.sm,
            background: "#450a0a",
            borderRadius: "4px",
            borderLeft: `3px solid ${colors.error}`,
          }}
        >
          <div style={{ fontWeight: 500, marginBottom: "4px" }}>{failure.name}</div>
          {failure.message && (
            <div style={{ fontSize: "13px", color: colors.muted, fontFamily: "monospace" }}>
              {failure.message}
            </div>
          )}
          {failure.file && (
            <div style={{ fontSize: "12px", color: colors.muted, marginTop: "4px" }}>
              {failure.file}
            </div>
          )}
        </div>
      ))}
    </div>
  );
}

export function BlockerCard({ element }: ComponentRenderProps) {
  const props = element.props as {
    title: string;
    description?: string;
    source?: string;
    iteration?: number;
  };

  return (
    <div
      style={{
        padding: spacing.md,
        background: "#422006",
        border: `1px solid ${colors.warning}`,
        borderRadius: "8px",
      }}
    >
      <div style={{ fontWeight: 600, marginBottom: props.description ? "8px" : 0 }}>
        {props.title}
      </div>
      {props.description && (
        <div style={{ fontSize: "14px", color: colors.muted, marginBottom: "8px" }}>
          {props.description}
        </div>
      )}
      <div style={{ display: "flex", gap: spacing.md, fontSize: "12px", color: colors.muted }}>
        {props.source && <span>Source: {props.source}</span>}
        {props.iteration && <span>Iteration {props.iteration}</span>}
      </div>
    </div>
  );
}

export function CostSummary({ element }: ComponentRenderProps) {
  const props = element.props as {
    totalUsd: number;
    iterations: number;
    breakdown?: Array<{ role: string; cost: number }>;
  };

  return (
    <div>
      <div style={{ display: "flex", alignItems: "baseline", gap: spacing.sm, marginBottom: spacing.md }}>
        <span style={{ fontSize: "24px", fontWeight: 700 }}>${props.totalUsd.toFixed(2)}</span>
        <span style={{ color: colors.muted }}>across {props.iterations} iterations</span>
      </div>
      {props.breakdown && props.breakdown.length > 0 && (
        <div style={{ display: "flex", flexDirection: "column", gap: "4px" }}>
          {props.breakdown.map((item) => (
            <div key={item.role} style={{ display: "flex", justifyContent: "space-between" }}>
              <span style={{ color: colors.muted }}>{item.role}</span>
              <span>${item.cost.toFixed(2)}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

// ===================
// Interactive
// ===================

export function Button({ element, onAction }: ComponentRenderProps) {
  const props = element.props as {
    label: string;
    variant?: "primary" | "secondary" | "danger" | "ghost";
    action: string;
    disabled?: boolean;
  };

  const variantStyles: Record<string, React.CSSProperties> = {
    primary: { background: colors.text, color: colors.bg },
    secondary: { background: "transparent", color: colors.text, border: `1px solid ${colors.border}` },
    danger: { background: colors.error, color: "#fff" },
    ghost: { background: "transparent", color: colors.muted },
  };

  return (
    <button
      type="button"
      disabled={props.disabled}
      onClick={() => onAction?.({ name: props.action })}
      style={{
        padding: "8px 16px",
        fontSize: "14px",
        fontWeight: 500,
        borderRadius: "6px",
        border: "none",
        cursor: props.disabled ? "not-allowed" : "pointer",
        opacity: props.disabled ? 0.5 : 1,
        ...variantStyles[props.variant || "primary"],
      }}
    >
      {props.label}
    </button>
  );
}

export function ActionBar({ element, onAction }: ComponentRenderProps) {
  const props = element.props as {
    actions: Array<{
      label: string;
      action: string;
      variant?: "primary" | "secondary" | "danger" | "ghost";
    }>;
  };

  return (
    <div style={{ display: "flex", gap: spacing.sm }}>
      {props.actions.map((action, i) => (
        <Button
          key={i}
          element={{
            ...element,
            props: {
              label: action.label,
              action: action.action,
              variant: action.variant || "secondary",
            },
          }}
          onAction={onAction}
        />
      ))}
    </div>
  );
}

// ===================
// Data Display
// ===================

export function KeyValue({ element }: ComponentRenderProps) {
  const props = element.props as {
    label: string;
    value: string;
  };

  return (
    <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
      <span style={{ color: colors.muted, fontSize: "13px" }}>{props.label}</span>
      <span style={{ fontWeight: 500 }}>{props.value}</span>
    </div>
  );
}

export function KeyValueList({ element }: ComponentRenderProps) {
  const props = element.props as {
    items: Array<{ label: string; value: string }>;
  };

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "8px" }}>
      {props.items.map((item, i) => (
        <KeyValue
          key={i}
          element={{
            ...element,
            props: item,
          }}
        />
      ))}
    </div>
  );
}

export function Divider({ element }: ComponentRenderProps) {
  const props = element.props as {
    label?: string;
  };

  if (props.label) {
    return (
      <div style={{ display: "flex", alignItems: "center", gap: spacing.md }}>
        <div style={{ flex: 1, height: "1px", background: colors.border }} />
        <span style={{ color: colors.muted, fontSize: "12px", textTransform: "uppercase" }}>
          {props.label}
        </span>
        <div style={{ flex: 1, height: "1px", background: colors.border }} />
      </div>
    );
  }

  return <div style={{ height: "1px", background: colors.border }} />;
}

export function EmptyState({ element, onAction }: ComponentRenderProps) {
  const props = element.props as {
    title: string;
    message?: string;
    action?: string;
    actionLabel?: string;
  };

  return (
    <div style={{ textAlign: "center", padding: spacing.lg }}>
      <div style={{ fontSize: "16px", fontWeight: 500, marginBottom: "8px" }}>{props.title}</div>
      {props.message && (
        <div style={{ color: colors.muted, fontSize: "14px", marginBottom: spacing.md }}>
          {props.message}
        </div>
      )}
      {props.action && props.actionLabel && (
        <Button
          element={{
            ...element,
            props: { label: props.actionLabel, action: props.action, variant: "secondary" },
          }}
          onAction={onAction}
        />
      )}
    </div>
  );
}

// ===================
// Registry Export
// ===================

export const superloopRegistry = {
  // Layout
  Stack,
  Card,
  Grid,
  // Typography
  Heading,
  Text,
  // Status
  Badge,
  Alert,
  // Superloop
  GateStatus,
  GateSummary,
  IterationHeader,
  TaskList,
  ProgressBar,
  TestFailures,
  BlockerCard,
  CostSummary,
  // Interactive
  Button,
  ActionBar,
  // Data
  KeyValue,
  KeyValueList,
  Divider,
  EmptyState,
};
