/**
 * OptionList - Single/multi-select option chooser
 * Ported from: https://github.com/assistant-ui/tool-ui
 *
 * Adapted for json-render integration
 */

import { useMemo, useState, useCallback, Fragment } from "react";
import type { ComponentRenderProps } from "@json-render/react";
import { cn } from "../../lib/cn.js";
import { Button } from "../../ui/button.js";
import { Separator } from "../../ui/separator.js";
import { Check } from "lucide-react";
import { ActionButtons, type Action } from "./shared/index.js";

interface OptionItem {
  id: string;
  label: string;
  description?: string;
  disabled?: boolean;
}

interface OptionListProps {
  id?: string;
  options: OptionItem[];
  selectionMode?: "single" | "multi";
  minSelections?: number;
  maxSelections?: number;
  defaultValue?: string | string[];
  confirmed?: string | string[] | null;
  isLoading?: boolean;
  className?: string;
}

function SelectionIndicator({
  mode,
  isSelected,
  disabled,
}: {
  mode: "multi" | "single";
  isSelected: boolean;
  disabled?: boolean;
}) {
  const shape = mode === "single" ? "rounded-full" : "rounded";

  return (
    <div
      className={cn(
        "flex size-4 shrink-0 items-center justify-center border-2 transition-colors",
        shape,
        isSelected && "border-primary bg-primary text-primary-foreground",
        !isSelected && "border-muted-foreground/50",
        disabled && "opacity-50",
      )}
    >
      {mode === "multi" && isSelected && <Check className="size-3" />}
      {mode === "single" && isSelected && (
        <span className="size-2 rounded-full bg-current" />
      )}
    </div>
  );
}

function OptionListConfirmation({
  id,
  options,
  selectedIds,
  className,
}: {
  id?: string;
  options: OptionItem[];
  selectedIds: Set<string>;
  className?: string;
}) {
  const confirmedOptions = options.filter((opt) => selectedIds.has(opt.id));

  return (
    <div
      className={cn(
        "flex w-full max-w-md min-w-80 flex-col",
        "text-foreground",
        className,
      )}
      data-slot="option-list"
      data-tool-ui-id={id}
      data-receipt="true"
      role="status"
      aria-label="Confirmed selection"
    >
      <div
        className={cn(
          "bg-card/60 flex w-full flex-col overflow-hidden rounded-2xl border px-5 py-2.5 opacity-95 shadow-sm",
        )}
      >
        {confirmedOptions.map((option, index) => (
          <Fragment key={option.id}>
            {index > 0 && <Separator orientation="horizontal" />}
            <div className="flex items-start gap-3 py-1">
              <span className="flex h-6 items-center">
                <Check className="text-primary size-4 shrink-0" />
              </span>
              <div className="flex flex-col text-left">
                <span className="text-base leading-6 font-medium text-pretty">
                  {option.label}
                </span>
                {option.description && (
                  <span className="text-muted-foreground text-sm font-normal text-pretty">
                    {option.description}
                  </span>
                )}
              </div>
            </div>
          </Fragment>
        ))}
      </div>
    </div>
  );
}

function OptionListSkeleton({ className }: { className?: string }) {
  return (
    <div
      className={cn("flex w-full max-w-md min-w-80 flex-col gap-3", className)}
      aria-busy="true"
    >
      <div className="bg-card flex w-full flex-col gap-3 rounded-2xl border p-4 shadow-sm">
        {[1, 2, 3].map((i) => (
          <div key={i} className="flex items-center gap-3">
            <div className="bg-muted size-4 animate-pulse rounded" />
            <div className="flex-1">
              <div className="bg-muted h-4 w-3/4 animate-pulse rounded" />
              <div className="bg-muted mt-1 h-3 w-1/2 animate-pulse rounded" />
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

export function OptionList({ element, onAction }: ComponentRenderProps) {
  const props = element.props as unknown as OptionListProps;
  const {
    id,
    options,
    selectionMode = "single",
    minSelections = 1,
    maxSelections,
    defaultValue,
    confirmed,
    isLoading,
    className,
  } = props;

  const effectiveMaxSelections = selectionMode === "single" ? 1 : maxSelections;

  // Parse initial selection
  const parseSelection = (
    value: string | string[] | undefined,
  ): Set<string> => {
    if (!value) return new Set();
    if (typeof value === "string") return new Set([value]);
    return new Set(value);
  };

  const [selectedIds, setSelectedIds] = useState<Set<string>>(() =>
    parseSelection(defaultValue),
  );

  const selectedCount = selectedIds.size;

  const toggleSelection = useCallback(
    (optionId: string) => {
      setSelectedIds((prev) => {
        const next = new Set(prev);
        const isSelected = next.has(optionId);

        if (selectionMode === "single") {
          if (isSelected) {
            next.delete(optionId);
          } else {
            next.clear();
            next.add(optionId);
          }
        } else {
          if (isSelected) {
            next.delete(optionId);
          } else {
            if (effectiveMaxSelections && next.size >= effectiveMaxSelections) {
              return prev;
            }
            next.add(optionId);
          }
        }

        return next;
      });
    },
    [selectionMode, effectiveMaxSelections],
  );

  const handleConfirm = useCallback(() => {
    if (selectedCount === 0 || selectedCount < minSelections) return;
    const selection =
      selectionMode === "single"
        ? Array.from(selectedIds)[0]
        : Array.from(selectedIds);
    onAction?.({ name: "confirm", params: { selected: selection } });
  }, [minSelections, onAction, selectedCount, selectedIds, selectionMode]);

  const handleCancel = useCallback(() => {
    setSelectedIds(new Set());
    onAction?.({ name: "cancel" });
  }, [onAction]);

  const handleAction = useCallback(
    (actionId: string) => {
      if (actionId === "confirm") {
        handleConfirm();
      } else if (actionId === "cancel") {
        handleCancel();
      } else {
        onAction?.({ name: actionId });
      }
    },
    [handleConfirm, handleCancel, onAction],
  );

  const isConfirmDisabled =
    selectedCount < minSelections || selectedCount === 0;
  const hasNothingToClear = selectedCount === 0;

  const actions: Action[] = useMemo(
    () => [
      {
        id: "cancel",
        label: "Clear",
        variant: "ghost" as const,
        disabled: hasNothingToClear,
      },
      {
        id: "confirm",
        label:
          selectionMode === "multi" && selectedCount > 0
            ? `Confirm (${selectedCount})`
            : "Confirm",
        variant: "default" as const,
        disabled: isConfirmDisabled,
      },
    ],
    [hasNothingToClear, selectionMode, selectedCount, isConfirmDisabled],
  );

  if (isLoading) {
    return <OptionListSkeleton className={className} />;
  }

  // Show confirmation receipt if confirmed
  if (confirmed !== undefined && confirmed !== null) {
    const confirmedSet = parseSelection(confirmed);
    return (
      <OptionListConfirmation
        id={id}
        options={options}
        selectedIds={confirmedSet}
        className={className}
      />
    );
  }

  return (
    <div
      className={cn(
        "flex w-full max-w-md min-w-80 flex-col gap-3",
        "text-foreground",
        className,
      )}
      data-slot="option-list"
      data-tool-ui-id={id}
      role="group"
      aria-label="Option list"
    >
      <div
        className={cn(
          "bg-card flex w-full flex-col overflow-hidden rounded-2xl border px-4 py-1.5 shadow-sm",
        )}
        role="listbox"
        aria-multiselectable={selectionMode === "multi"}
      >
        {options.map((option, index) => {
          const isSelected = selectedIds.has(option.id);
          const isSelectionLocked =
            selectionMode === "multi" &&
            effectiveMaxSelections !== undefined &&
            selectedCount >= effectiveMaxSelections &&
            !isSelected;
          const isDisabled = option.disabled || isSelectionLocked;

          return (
            <Fragment key={option.id}>
              {index > 0 && <Separator orientation="horizontal" />}
              <Button
                variant="ghost"
                role="option"
                aria-selected={isSelected}
                onClick={() => toggleSelection(option.id)}
                disabled={isDisabled}
                className={cn(
                  "h-auto min-h-[50px] w-full justify-start text-left font-medium",
                  "rounded-none border-0 bg-transparent px-0 py-2 shadow-none hover:bg-transparent",
                )}
              >
                <div className="flex items-start gap-3">
                  <span className="flex h-6 items-center">
                    <SelectionIndicator
                      mode={selectionMode}
                      isSelected={isSelected}
                      disabled={option.disabled}
                    />
                  </span>
                  <div className="flex flex-col text-left">
                    <span className="leading-6 text-pretty">{option.label}</span>
                    {option.description && (
                      <span className="text-muted-foreground text-sm font-normal text-pretty">
                        {option.description}
                      </span>
                    )}
                  </div>
                </div>
              </Button>
            </Fragment>
          );
        })}
      </div>

      <ActionButtons actions={actions} onAction={handleAction} align="right" />
    </div>
  );
}
