/**
 * Terminal - Command-line output display
 * Ported from: https://github.com/assistant-ui/tool-ui
 *
 * Adapted for json-render integration
 */

import { useMemo, useState, useCallback } from "react";
import type { ComponentRenderProps } from "@json-render/react";
import Ansi from "ansi-to-react";
import {
  Copy,
  Check,
  ChevronDown,
  ChevronUp,
  Terminal as TerminalIcon,
} from "lucide-react";
import { cn } from "../../lib/cn.js";
import { Button } from "../../ui/button.js";
import { Collapsible, CollapsibleTrigger } from "../../ui/collapsible.js";
import {
  ActionButtons,
  normalizeActionsConfig,
  useCopyToClipboard,
  type ActionsProp,
} from "./shared/index.js";

interface TerminalProps {
  id?: string;
  command: string;
  stdout?: string;
  stderr?: string;
  exitCode?: number;
  durationMs?: number;
  cwd?: string;
  truncated?: boolean;
  maxCollapsedLines?: number;
  responseActions?: ActionsProp;
  isLoading?: boolean;
  className?: string;
}

function TerminalProgress() {
  return (
    <div className="flex w-full animate-pulse flex-col gap-3 p-4">
      <div className="flex items-center gap-2">
        <div className="bg-muted h-4 w-4 rounded" />
        <div className="bg-muted h-3 w-48 rounded" />
      </div>
      <div className="bg-muted h-20 w-full rounded" />
    </div>
  );
}

export function Terminal({ element, onAction }: ComponentRenderProps) {
  const props = element.props as unknown as TerminalProps;
  const {
    id,
    command,
    stdout,
    stderr,
    exitCode,
    cwd,
    truncated,
    maxCollapsedLines,
    responseActions,
    isLoading,
    className,
  } = props;

  const [isExpanded, setIsExpanded] = useState(false);
  const { copiedId, copy } = useCopyToClipboard();

  const COPY_ID = "terminal-output";
  const isSuccess = exitCode === 0;
  const hasOutput = stdout || stderr;
  const fullOutput = [stdout, stderr].filter(Boolean).join("\n");

  const lineCount = fullOutput.split("\n").length;
  const shouldCollapse = maxCollapsedLines && lineCount > maxCollapsedLines;
  const isCollapsed = shouldCollapse && !isExpanded;

  const normalizedFooterActions = useMemo(
    () => normalizeActionsConfig(responseActions),
    [responseActions],
  );

  const handleCopy = useCallback(() => {
    copy(fullOutput, COPY_ID);
    onAction?.({ name: "copy_output", params: { output: fullOutput } });
  }, [fullOutput, copy, onAction]);

  const handleResponseAction = useCallback(
    (actionId: string) => {
      onAction?.({ name: actionId });
    },
    [onAction],
  );

  if (isLoading) {
    return (
      <div
        className={cn("flex w-full min-w-80 flex-col gap-3", className)}
        data-tool-ui-id={id}
        aria-busy="true"
      >
        <div className="border-border bg-card overflow-hidden rounded-lg border shadow-sm">
          <TerminalProgress />
        </div>
      </div>
    );
  }

  return (
    <div
      className={cn("flex w-full min-w-80 flex-col gap-3", className)}
      data-tool-ui-id={id}
      data-slot="terminal"
    >
      <div className="border-border bg-card overflow-hidden rounded-lg border shadow-sm">
        <div className="bg-card flex items-center justify-between border-b px-4 py-2">
          <div className="flex items-center gap-2 overflow-hidden">
            <TerminalIcon className="text-muted-foreground h-4 w-4 shrink-0" />
            <code className="text-foreground truncate font-mono text-xs">
              {cwd && <span className="text-muted-foreground">{cwd}$ </span>}
              {command}
            </code>
          </div>
          <div className="flex items-center gap-3">
            {exitCode !== undefined && (
              <span
                className={cn(
                  "font-mono text-sm tabular-nums",
                  isSuccess
                    ? "text-muted-foreground"
                    : "text-red-400",
                )}
              >
                {exitCode}
              </span>
            )}
            <Button
              variant="ghost"
              size="sm"
              onClick={handleCopy}
              className="h-7 w-7 p-0"
              aria-label={copiedId === COPY_ID ? "Copied" : "Copy output"}
            >
              {copiedId === COPY_ID ? (
                <Check className="h-4 w-4 text-green-400" />
              ) : (
                <Copy className="text-muted-foreground h-4 w-4" />
              )}
            </Button>
          </div>
        </div>

        {hasOutput && (
          <Collapsible open={!isCollapsed}>
            <div
              className={cn(
                "relative font-mono text-sm",
                isCollapsed && "max-h-[200px] overflow-hidden",
              )}
            >
              <div className="overflow-x-auto p-4">
                {stdout && (
                  <div className="text-foreground break-all whitespace-pre-wrap">
                    <Ansi>{stdout}</Ansi>
                  </div>
                )}
                {stderr && (
                  <div className="mt-2 break-all whitespace-pre-wrap text-red-400">
                    <Ansi>{stderr}</Ansi>
                  </div>
                )}
                {truncated && (
                  <div className="text-muted-foreground mt-2 text-xs italic">
                    Output truncated...
                  </div>
                )}
              </div>

              {isCollapsed && (
                <div className="from-card absolute inset-x-0 bottom-0 h-16 bg-gradient-to-t to-transparent" />
              )}
            </div>

            {shouldCollapse && (
              <CollapsibleTrigger asChild>
                <Button
                  variant="ghost"
                  onClick={() => setIsExpanded(!isExpanded)}
                  className="text-muted-foreground w-full rounded-none border-t font-normal"
                >
                  {isCollapsed ? (
                    <>
                      <ChevronDown className="mr-1 size-4" />
                      Show all {lineCount} lines
                    </>
                  ) : (
                    <>
                      <ChevronUp className="mr-1 size-4" />
                      Collapse
                    </>
                  )}
                </Button>
              </CollapsibleTrigger>
            )}
          </Collapsible>
        )}

        {!hasOutput && (
          <div className="text-muted-foreground px-4 py-3 font-mono text-sm italic">
            No output
          </div>
        )}
      </div>

      {normalizedFooterActions && (
        <div className="mt-3">
          <ActionButtons
            actions={normalizedFooterActions.items}
            align={normalizedFooterActions.align}
            confirmTimeout={normalizedFooterActions.confirmTimeout}
            onAction={handleResponseAction}
          />
        </div>
      )}
    </div>
  );
}
