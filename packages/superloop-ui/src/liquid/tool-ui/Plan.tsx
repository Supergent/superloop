/**
 * Plan - Step-by-step task workflow visualization
 * Ported from: https://github.com/assistant-ui/tool-ui
 *
 * Adapted for json-render integration
 */

import { useMemo } from "react";
import type { ComponentRenderProps } from "@json-render/react";
import {
  Circle,
  CircleDotDashed,
  CheckCircle2,
  XCircle,
  MoreHorizontal,
  ChevronRight,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";
import { cn } from "../../lib/cn.js";
import {
  Card,
  CardHeader,
  CardTitle,
  CardDescription,
  CardContent,
  CardFooter,
} from "../../ui/card.js";
import {
  Accordion,
  AccordionItem,
  AccordionTrigger,
  AccordionContent,
} from "../../ui/accordion.js";
import {
  Collapsible,
  CollapsibleTrigger,
  CollapsibleContent,
} from "../../ui/collapsible.js";
import {
  ActionButtons,
  normalizeActionsConfig,
  type ActionsProp,
} from "./shared/index.js";

type PlanTodoStatus = "pending" | "in_progress" | "completed" | "cancelled";

interface PlanTodo {
  id: string;
  label: string;
  description?: string;
  status: PlanTodoStatus;
}

interface PlanProps {
  id?: string;
  title: string;
  description?: string;
  todos: PlanTodo[];
  maxVisibleTodos?: number;
  showProgress?: boolean;
  responseActions?: ActionsProp;
  isLoading?: boolean;
  className?: string;
}

const INITIAL_VISIBLE_TODO_COUNT = 4;

interface TodoStatusStyle {
  icon: LucideIcon;
  iconClassName: string;
  labelClassName: string;
}

const TODO_STATUS_STYLES: Record<PlanTodoStatus, TodoStatusStyle> = {
  pending: {
    icon: Circle,
    iconClassName: "text-muted-foreground",
    labelClassName: "",
  },
  in_progress: {
    icon: CircleDotDashed,
    iconClassName: "text-primary",
    labelClassName: "text-primary/80",
  },
  completed: {
    icon: CheckCircle2,
    iconClassName: "text-emerald-500",
    labelClassName: "text-muted-foreground line-through",
  },
  cancelled: {
    icon: XCircle,
    iconClassName: "text-destructive/70",
    labelClassName: "text-muted-foreground line-through",
  },
};

function TodoIcon({
  icon: Icon,
  className,
  isAnimating,
}: {
  icon: LucideIcon;
  className: string;
  isAnimating?: boolean;
}) {
  return (
    <span
      className={cn(
        "mt-0.5 inline-flex shrink-0",
        isAnimating && "animate-spin",
      )}
      style={isAnimating ? { animationDuration: "8s" } : undefined}
    >
      <Icon className={cn("h-4 w-4 shrink-0", className)} />
    </span>
  );
}

function PlanTodoItem({ todo }: { todo: PlanTodo }) {
  const { icon, iconClassName, labelClassName } =
    TODO_STATUS_STYLES[todo.status];
  const isInProgress = todo.status === "in_progress";

  const labelElement = (
    <span className={cn("text-sm", labelClassName)}>{todo.label}</span>
  );

  if (!todo.description) {
    return (
      <li className="-mx-2 flex cursor-default items-start gap-2 rounded-md px-2 py-2">
        <TodoIcon
          icon={icon}
          className={iconClassName}
          isAnimating={isInProgress}
        />
        {labelElement}
      </li>
    );
  }

  return (
    <li className="hover:bg-muted -mx-2 cursor-default rounded-md">
      <Collapsible>
        <CollapsibleTrigger className="group/todo flex w-full cursor-default items-start gap-2 px-2 py-2 text-left">
          <TodoIcon
            icon={icon}
            className={iconClassName}
            isAnimating={isInProgress}
          />
          <span className={cn("flex-1 text-sm text-pretty", labelClassName)}>
            {todo.label}
          </span>
          <ChevronRight className="text-muted-foreground/50 mt-0.5 size-4 shrink-0 rotate-90 transition-transform duration-150 group-data-[state=open]/todo:[transform:rotateY(180deg)]" />
        </CollapsibleTrigger>
        <CollapsibleContent>
          <p className="text-muted-foreground pr-2 pb-1.5 pl-8 text-sm text-pretty">
            {todo.description}
          </p>
        </CollapsibleContent>
      </Collapsible>
    </li>
  );
}

function TodoList({ todos }: { todos: PlanTodo[] }) {
  return (
    <>
      {todos.map((todo) => (
        <PlanTodoItem key={todo.id} todo={todo} />
      ))}
    </>
  );
}

function ProgressBar({
  progress,
  isCelebrating,
}: {
  progress: number;
  isCelebrating: boolean;
}) {
  return (
    <div className="bg-muted mb-3 h-1.5 overflow-hidden rounded-full">
      <div
        className={cn(
          "h-full transition-all duration-500",
          isCelebrating ? "bg-emerald-500" : "bg-primary",
        )}
        style={{ width: `${progress}%` }}
      />
    </div>
  );
}

function PlanSkeleton({ className }: { className?: string }) {
  return (
    <Card className={cn("w-full max-w-xl min-w-80 gap-4 py-4", className)}>
      <CardHeader>
        <div className="bg-muted h-5 w-3/4 animate-pulse rounded" />
        <div className="bg-muted mt-2 h-4 w-1/2 animate-pulse rounded" />
      </CardHeader>
      <CardContent className="px-4">
        <div className="bg-muted/70 rounded-lg border px-4 py-3">
          <div className="bg-muted mb-3 h-1.5 animate-pulse rounded-full" />
          {[1, 2, 3].map((i) => (
            <div key={i} className="flex items-center gap-2 py-2">
              <div className="bg-muted size-4 animate-pulse rounded-full" />
              <div className="bg-muted h-4 flex-1 animate-pulse rounded" />
            </div>
          ))}
        </div>
      </CardContent>
    </Card>
  );
}

export function Plan({ element, onAction }: ComponentRenderProps) {
  const props = element.props as unknown as PlanProps;
  const {
    id,
    title,
    description,
    todos,
    maxVisibleTodos = INITIAL_VISIBLE_TODO_COUNT,
    showProgress = true,
    responseActions,
    isLoading,
    className,
  } = props;

  const { visibleTodos, hiddenTodos, completedCount, allComplete, progress } =
    useMemo(() => {
      const completed = todos.filter((t) => t.status === "completed").length;
      return {
        visibleTodos: todos.slice(0, maxVisibleTodos),
        hiddenTodos: todos.slice(maxVisibleTodos),
        completedCount: completed,
        allComplete: completed === todos.length && todos.length > 0,
        progress: todos.length > 0 ? (completed / todos.length) * 100 : 0,
      };
    }, [todos, maxVisibleTodos]);

  const resolvedFooterActions = useMemo(
    () => normalizeActionsConfig(responseActions),
    [responseActions],
  );

  const handleAction = (actionId: string) => {
    onAction?.({ name: actionId });
  };

  if (isLoading) {
    return <PlanSkeleton className={className} />;
  }

  return (
    <Card
      className={cn("w-full max-w-xl min-w-80 gap-4 py-4", className)}
      data-tool-ui-id={id}
      data-slot="plan"
    >
      <CardHeader className="flex flex-row items-start justify-between gap-4">
        <div className="space-y-1.5">
          <CardTitle className="leading-5 font-medium text-pretty">
            {title}
          </CardTitle>
          {description && <CardDescription>{description}</CardDescription>}
        </div>
        {allComplete && (
          <CheckCircle2 className="mt-0.5 size-5 shrink-0 text-emerald-500" />
        )}
      </CardHeader>

      <CardContent className="px-4">
        <div className="bg-muted/70 rounded-lg border px-4 py-3">
          {showProgress && (
            <>
              <div className="text-muted-foreground mb-2 text-sm">
                {completedCount} of {todos.length} complete
              </div>

              <ProgressBar progress={progress} isCelebrating={allComplete} />
            </>
          )}

          <ul className="space-y-0">
            <TodoList todos={visibleTodos} />

            {hiddenTodos.length > 0 && (
              <li className="mt-1">
                <Accordion type="single" collapsible>
                  <AccordionItem value="more" className="border-0">
                    <AccordionTrigger className="text-muted-foreground hover:text-primary flex cursor-default items-start justify-start gap-2 py-1 text-sm font-normal [&>svg:last-child]:hidden">
                      <MoreHorizontal className="text-muted-foreground/70 mt-0.5 size-4 shrink-0" />
                      <span>{hiddenTodos.length} more</span>
                    </AccordionTrigger>
                    <AccordionContent className="pt-2 pb-0">
                      <ul className="-mx-2 space-y-2 px-2">
                        <TodoList todos={hiddenTodos} />
                      </ul>
                    </AccordionContent>
                  </AccordionItem>
                </Accordion>
              </li>
            )}
          </ul>
        </div>
      </CardContent>

      {resolvedFooterActions && (
        <CardFooter>
          <ActionButtons
            actions={resolvedFooterActions.items}
            align={resolvedFooterActions.align}
            confirmTimeout={resolvedFooterActions.confirmTimeout}
            onAction={handleAction}
            className="w-full"
          />
        </CardFooter>
      )}
    </Card>
  );
}
