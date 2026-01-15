import { z } from "zod";
import type { DynamicValue, DataModel } from "./types";
import { DynamicValueSchema, resolveDynamicValue } from "./types";

/**
 * Confirmation dialog configuration
 */
export interface ActionConfirm {
  title: string;
  message: string;
  confirmLabel?: string;
  cancelLabel?: string;
  variant?: "default" | "danger";
}

/**
 * Action success handler
 */
export type ActionOnSuccess =
  | { navigate: string }
  | { set: Record<string, unknown> }
  | { action: string };

/**
 * Action error handler
 */
export type ActionOnError =
  | { set: Record<string, unknown> }
  | { action: string };

/**
 * Rich action definition
 */
export interface Action {
  /** Action name (must be in catalog) */
  name: string;
  /** Parameters to pass to the action handler */
  params?: Record<string, DynamicValue>;
  /** Confirmation dialog before execution */
  confirm?: ActionConfirm;
  /** Handler after successful execution */
  onSuccess?: ActionOnSuccess;
  /** Handler after failed execution */
  onError?: ActionOnError;
}

/**
 * Schema for action confirmation
 */
export const ActionConfirmSchema = z.object({
  title: z.string(),
  message: z.string(),
  confirmLabel: z.string().optional(),
  cancelLabel: z.string().optional(),
  variant: z.enum(["default", "danger"]).optional(),
});

/**
 * Schema for success handlers
 */
export const ActionOnSuccessSchema = z.union([
  z.object({ navigate: z.string() }),
  z.object({ set: z.record(z.string(), z.unknown()) }),
  z.object({ action: z.string() }),
]);

/**
 * Schema for error handlers
 */
export const ActionOnErrorSchema = z.union([
  z.object({ set: z.record(z.string(), z.unknown()) }),
  z.object({ action: z.string() }),
]);

/**
 * Full action schema
 */
export const ActionSchema = z.object({
  name: z.string(),
  params: z.record(z.string(), DynamicValueSchema).optional(),
  confirm: ActionConfirmSchema.optional(),
  onSuccess: ActionOnSuccessSchema.optional(),
  onError: ActionOnErrorSchema.optional(),
});

/**
 * Action handler function signature
 */
export type ActionHandler<
  TParams = Record<string, unknown>,
  TResult = unknown,
> = (params: TParams) => Promise<TResult> | TResult;

/**
 * Action definition in catalog
 */
export interface ActionDefinition<TParams = Record<string, unknown>> {
  /** Zod schema for params validation */
  params?: z.ZodType<TParams>;
  /** Description for AI */
  description?: string;
}

/**
 * Resolved action with all dynamic values resolved
 */
export interface ResolvedAction {
  name: string;
  params: Record<string, unknown>;
  confirm?: ActionConfirm;
  onSuccess?: ActionOnSuccess;
  onError?: ActionOnError;
}

/**
 * Resolve all dynamic values in an action
 */
export function resolveAction(
  action: Action,
  dataModel: DataModel,
): ResolvedAction {
  const resolvedParams: Record<string, unknown> = {};

  if (action.params) {
    for (const [key, value] of Object.entries(action.params)) {
      resolvedParams[key] = resolveDynamicValue(value, dataModel);
    }
  }

  // Interpolate confirmation message if present
  let confirm = action.confirm;
  if (confirm) {
    confirm = {
      ...confirm,
      message: interpolateString(confirm.message, dataModel),
      title: interpolateString(confirm.title, dataModel),
    };
  }

  return {
    name: action.name,
    params: resolvedParams,
    confirm,
    onSuccess: action.onSuccess,
    onError: action.onError,
  };
}

/**
 * Interpolate ${path} expressions in a string
 */
export function interpolateString(
  template: string,
  dataModel: DataModel,
): string {
  return template.replace(/\$\{([^}]+)\}/g, (_, path) => {
    const value = resolveDynamicValue({ path }, dataModel);
    return String(value ?? "");
  });
}

/**
 * Context for action execution
 */
export interface ActionExecutionContext {
  /** The resolved action */
  action: ResolvedAction;
  /** The action handler from the host */
  handler: ActionHandler;
  /** Function to update data model */
  setData: (path: string, value: unknown) => void;
  /** Function to navigate */
  navigate?: (path: string) => void;
  /** Function to execute another action */
  executeAction?: (name: string) => Promise<void>;
}

/**
 * Execute an action with all callbacks
 */
export async function executeAction(
  ctx: ActionExecutionContext,
): Promise<void> {
  const { action, handler, setData, navigate, executeAction } = ctx;

  try {
    await handler(action.params);

    // Handle success
    if (action.onSuccess) {
      if ("navigate" in action.onSuccess && navigate) {
        navigate(action.onSuccess.navigate);
      } else if ("set" in action.onSuccess) {
        for (const [path, value] of Object.entries(action.onSuccess.set)) {
          setData(path, value);
        }
      } else if ("action" in action.onSuccess && executeAction) {
        await executeAction(action.onSuccess.action);
      }
    }
  } catch (error) {
    // Handle error
    if (action.onError) {
      if ("set" in action.onError) {
        for (const [path, value] of Object.entries(action.onError.set)) {
          // Replace $error.message with actual error
          const resolvedValue =
            typeof value === "string" && value === "$error.message"
              ? (error as Error).message
              : value;
          setData(path, resolvedValue);
        }
      } else if ("action" in action.onError && executeAction) {
        await executeAction(action.onError.action);
      }
    } else {
      throw error;
    }
  }
}

/**
 * Helper to create actions
 */
export const action = {
  /** Create a simple action */
  simple: (name: string, params?: Record<string, DynamicValue>): Action => ({
    name,
    params,
  }),

  /** Create an action with confirmation */
  withConfirm: (
    name: string,
    confirm: ActionConfirm,
    params?: Record<string, DynamicValue>,
  ): Action => ({
    name,
    params,
    confirm,
  }),

  /** Create an action with success handler */
  withSuccess: (
    name: string,
    onSuccess: ActionOnSuccess,
    params?: Record<string, DynamicValue>,
  ): Action => ({
    name,
    params,
    onSuccess,
  }),
};
