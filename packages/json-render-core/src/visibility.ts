import { z } from "zod";
import type {
  VisibilityCondition,
  LogicExpression,
  DataModel,
  AuthState,
  DynamicValue,
} from "./types";
import { resolveDynamicValue, DynamicValueSchema } from "./types";

// Dynamic value schema for comparisons (number-focused)
const DynamicNumberValueSchema = z.union([
  z.number(),
  z.object({ path: z.string() }),
]);

/**
 * Logic expression schema (recursive)
 * Using a more permissive schema that aligns with runtime behavior
 */
export const LogicExpressionSchema: z.ZodType<LogicExpression> = z.lazy(() =>
  z.union([
    z.object({ and: z.array(LogicExpressionSchema) }),
    z.object({ or: z.array(LogicExpressionSchema) }),
    z.object({ not: LogicExpressionSchema }),
    z.object({ path: z.string() }),
    z.object({ eq: z.tuple([DynamicValueSchema, DynamicValueSchema]) }),
    z.object({ neq: z.tuple([DynamicValueSchema, DynamicValueSchema]) }),
    z.object({
      gt: z.tuple([DynamicNumberValueSchema, DynamicNumberValueSchema]),
    }),
    z.object({
      gte: z.tuple([DynamicNumberValueSchema, DynamicNumberValueSchema]),
    }),
    z.object({
      lt: z.tuple([DynamicNumberValueSchema, DynamicNumberValueSchema]),
    }),
    z.object({
      lte: z.tuple([DynamicNumberValueSchema, DynamicNumberValueSchema]),
    }),
  ]),
) as z.ZodType<LogicExpression>;

/**
 * Visibility condition schema
 */
export const VisibilityConditionSchema: z.ZodType<VisibilityCondition> =
  z.union([
    z.boolean(),
    z.object({ path: z.string() }),
    z.object({ auth: z.enum(["signedIn", "signedOut"]) }),
    LogicExpressionSchema,
  ]);

/**
 * Context for evaluating visibility
 */
export interface VisibilityContext {
  dataModel: DataModel;
  authState?: AuthState;
}

/**
 * Evaluate a logic expression against data and auth state
 */
export function evaluateLogicExpression(
  expr: LogicExpression,
  ctx: VisibilityContext,
): boolean {
  const { dataModel } = ctx;

  // AND expression
  if ("and" in expr) {
    return expr.and.every((subExpr) => evaluateLogicExpression(subExpr, ctx));
  }

  // OR expression
  if ("or" in expr) {
    return expr.or.some((subExpr) => evaluateLogicExpression(subExpr, ctx));
  }

  // NOT expression
  if ("not" in expr) {
    return !evaluateLogicExpression(expr.not, ctx);
  }

  // Path expression (resolve to boolean)
  if ("path" in expr) {
    const value = resolveDynamicValue({ path: expr.path }, dataModel);
    return Boolean(value);
  }

  // Equality comparison
  if ("eq" in expr) {
    const [left, right] = expr.eq;
    const leftValue = resolveDynamicValue(left, dataModel);
    const rightValue = resolveDynamicValue(right, dataModel);
    return leftValue === rightValue;
  }

  // Not equal comparison
  if ("neq" in expr) {
    const [left, right] = expr.neq;
    const leftValue = resolveDynamicValue(left, dataModel);
    const rightValue = resolveDynamicValue(right, dataModel);
    return leftValue !== rightValue;
  }

  // Greater than
  if ("gt" in expr) {
    const [left, right] = expr.gt;
    const leftValue = resolveDynamicValue(
      left as DynamicValue<number>,
      dataModel,
    );
    const rightValue = resolveDynamicValue(
      right as DynamicValue<number>,
      dataModel,
    );
    if (typeof leftValue === "number" && typeof rightValue === "number") {
      return leftValue > rightValue;
    }
    return false;
  }

  // Greater than or equal
  if ("gte" in expr) {
    const [left, right] = expr.gte;
    const leftValue = resolveDynamicValue(
      left as DynamicValue<number>,
      dataModel,
    );
    const rightValue = resolveDynamicValue(
      right as DynamicValue<number>,
      dataModel,
    );
    if (typeof leftValue === "number" && typeof rightValue === "number") {
      return leftValue >= rightValue;
    }
    return false;
  }

  // Less than
  if ("lt" in expr) {
    const [left, right] = expr.lt;
    const leftValue = resolveDynamicValue(
      left as DynamicValue<number>,
      dataModel,
    );
    const rightValue = resolveDynamicValue(
      right as DynamicValue<number>,
      dataModel,
    );
    if (typeof leftValue === "number" && typeof rightValue === "number") {
      return leftValue < rightValue;
    }
    return false;
  }

  // Less than or equal
  if ("lte" in expr) {
    const [left, right] = expr.lte;
    const leftValue = resolveDynamicValue(
      left as DynamicValue<number>,
      dataModel,
    );
    const rightValue = resolveDynamicValue(
      right as DynamicValue<number>,
      dataModel,
    );
    if (typeof leftValue === "number" && typeof rightValue === "number") {
      return leftValue <= rightValue;
    }
    return false;
  }

  return false;
}

/**
 * Evaluate a visibility condition
 */
export function evaluateVisibility(
  condition: VisibilityCondition | undefined,
  ctx: VisibilityContext,
): boolean {
  // No condition = visible
  if (condition === undefined) {
    return true;
  }

  // Boolean literal
  if (typeof condition === "boolean") {
    return condition;
  }

  // Path reference
  if ("path" in condition && !("and" in condition) && !("or" in condition)) {
    const value = resolveDynamicValue({ path: condition.path }, ctx.dataModel);
    return Boolean(value);
  }

  // Auth condition
  if ("auth" in condition) {
    const isSignedIn = ctx.authState?.isSignedIn ?? false;
    if (condition.auth === "signedIn") {
      return isSignedIn;
    }
    if (condition.auth === "signedOut") {
      return !isSignedIn;
    }
    return false;
  }

  // Logic expression
  return evaluateLogicExpression(condition as LogicExpression, ctx);
}

/**
 * Helper to create visibility conditions
 */
export const visibility = {
  /** Always visible */
  always: true as const,

  /** Never visible */
  never: false as const,

  /** Visible when path is truthy */
  when: (path: string): VisibilityCondition => ({ path }),

  /** Visible when signed in */
  signedIn: { auth: "signedIn" } as const,

  /** Visible when signed out */
  signedOut: { auth: "signedOut" } as const,

  /** AND multiple conditions */
  and: (...conditions: LogicExpression[]): LogicExpression => ({
    and: conditions,
  }),

  /** OR multiple conditions */
  or: (...conditions: LogicExpression[]): LogicExpression => ({
    or: conditions,
  }),

  /** NOT a condition */
  not: (condition: LogicExpression): LogicExpression => ({ not: condition }),

  /** Equality check */
  eq: (left: DynamicValue, right: DynamicValue): LogicExpression => ({
    eq: [left, right],
  }),

  /** Not equal check */
  neq: (left: DynamicValue, right: DynamicValue): LogicExpression => ({
    neq: [left, right],
  }),

  /** Greater than */
  gt: (
    left: DynamicValue<number>,
    right: DynamicValue<number>,
  ): LogicExpression => ({ gt: [left, right] }),

  /** Greater than or equal */
  gte: (
    left: DynamicValue<number>,
    right: DynamicValue<number>,
  ): LogicExpression => ({ gte: [left, right] }),

  /** Less than */
  lt: (
    left: DynamicValue<number>,
    right: DynamicValue<number>,
  ): LogicExpression => ({ lt: [left, right] }),

  /** Less than or equal */
  lte: (
    left: DynamicValue<number>,
    right: DynamicValue<number>,
  ): LogicExpression => ({ lte: [left, right] }),
};
