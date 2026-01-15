/**
 * DataTable - Sortable data table with mobile card layout
 * Ported from: https://github.com/assistant-ui/tool-ui
 *
 * Adapted for json-render integration
 * Simplified version focusing on core table functionality
 */

import * as React from "react";
import type { ComponentRenderProps } from "@json-render/react";
import { ArrowUp, ArrowDown, ArrowUpDown } from "lucide-react";
import { cn } from "../../lib/cn.js";
import {
  Table,
  TableBody,
  TableRow,
  TableCell,
  TableHeader,
  TableHead,
} from "../../ui/table.js";
import { Button } from "../../ui/button.js";
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "../../ui/accordion.js";
import {
  ActionButtons,
  normalizeActionsConfig,
  type ActionsProp,
} from "./shared/index.js";

interface Column {
  key: string;
  label: string;
  sortable?: boolean;
  width?: string;
  align?: "left" | "center" | "right";
  priority?: "primary" | "secondary" | "tertiary";
}

interface DataTableProps {
  id?: string;
  columns: Column[];
  data: Record<string, unknown>[];
  rowIdKey?: string;
  layout?: "auto" | "table" | "cards";
  defaultSort?: { by: string; direction: "asc" | "desc" };
  emptyMessage?: string;
  maxHeight?: string;
  locale?: string;
  responseActions?: ActionsProp;
  isLoading?: boolean;
  className?: string;
}

type SortDirection = "asc" | "desc" | undefined;

function getAlignmentClass(align?: "left" | "center" | "right"): string {
  if (align === "right") return "text-right";
  if (align === "center") return "text-center";
  return "text-left";
}

function formatCellValue(value: unknown): string {
  if (value === null || value === undefined) return "—";
  if (typeof value === "number") {
    return value.toLocaleString();
  }
  if (typeof value === "boolean") {
    return value ? "Yes" : "No";
  }
  if (value instanceof Date) {
    return value.toLocaleDateString();
  }
  return String(value);
}

function sortData<T extends Record<string, unknown>>(
  data: T[],
  sortBy: string,
  direction: "asc" | "desc",
  locale: string,
): T[] {
  return [...data].sort((a, b) => {
    const aVal = a[sortBy];
    const bVal = b[sortBy];

    if (aVal === bVal) return 0;
    if (aVal === null || aVal === undefined) return 1;
    if (bVal === null || bVal === undefined) return -1;

    let comparison: number;
    if (typeof aVal === "number" && typeof bVal === "number") {
      comparison = aVal - bVal;
    } else {
      comparison = String(aVal).localeCompare(String(bVal), locale);
    }

    return direction === "asc" ? comparison : -comparison;
  });
}

function DataTableSkeleton({ columns }: { columns: Column[] }) {
  return (
    <Table>
      <TableHeader>
        <TableRow>
          {columns.map((col) => (
            <TableHead key={col.key}>
              <div className="bg-muted h-4 w-20 animate-pulse rounded" />
            </TableHead>
          ))}
        </TableRow>
      </TableHeader>
      <TableBody>
        {[1, 2, 3].map((row) => (
          <TableRow key={row}>
            {columns.map((col) => (
              <TableCell key={col.key}>
                <div className="bg-muted h-4 w-full animate-pulse rounded" />
              </TableCell>
            ))}
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}

function MobileCardSkeleton() {
  return (
    <div className="space-y-2">
      {[1, 2, 3].map((i) => (
        <div
          key={i}
          className="bg-card animate-pulse rounded-lg border p-4"
        >
          <div className="bg-muted mb-2 h-5 w-1/2 rounded" />
          <div className="bg-muted h-4 w-full rounded" />
        </div>
      ))}
    </div>
  );
}

export function DataTable({ element, onAction }: ComponentRenderProps) {
  const props = element.props as unknown as DataTableProps;
  const {
    id,
    columns,
    data: rawData,
    rowIdKey = "id",
    layout = "auto",
    defaultSort,
    emptyMessage = "No data available",
    maxHeight,
    locale = "en-US",
    responseActions,
    isLoading,
    className,
  } = props;

  const [sortBy, setSortBy] = React.useState<string | undefined>(
    defaultSort?.by,
  );
  const [sortDirection, setSortDirection] = React.useState<SortDirection>(
    defaultSort?.direction,
  );

  const data = React.useMemo(() => {
    if (!sortBy || !sortDirection) return rawData;
    return sortData(rawData, sortBy, sortDirection, locale);
  }, [rawData, sortBy, sortDirection, locale]);

  const handleSort = React.useCallback(
    (key: string) => {
      if (sortBy === key) {
        if (sortDirection === "asc") {
          setSortDirection("desc");
        } else if (sortDirection === "desc") {
          setSortBy(undefined);
          setSortDirection(undefined);
        } else {
          setSortDirection("asc");
        }
      } else {
        setSortBy(key);
        setSortDirection("asc");
      }
    },
    [sortBy, sortDirection],
  );

  const normalizedActions = React.useMemo(
    () => normalizeActionsConfig(responseActions),
    [responseActions],
  );

  const handleAction = React.useCallback(
    (actionId: string) => {
      onAction?.({ name: actionId });
    },
    [onAction],
  );

  const handleRowClick = React.useCallback(
    (row: Record<string, unknown>) => {
      onAction?.({ name: "row_click", params: { row } });
    },
    [onAction],
  );

  // Categorize columns for mobile view
  const primaryColumns = columns.filter(
    (c) => c.priority === "primary" || !c.priority,
  );
  const secondaryColumns = columns.filter((c) => c.priority === "secondary");

  const renderSortIcon = (col: Column) => {
    if (!col.sortable) return null;
    if (sortBy !== col.key) {
      return <ArrowUpDown className="ml-1 h-3 w-3 opacity-50" />;
    }
    return sortDirection === "asc" ? (
      <ArrowUp className="ml-1 h-3 w-3" />
    ) : (
      <ArrowDown className="ml-1 h-3 w-3" />
    );
  };

  if (isLoading) {
    return (
      <div
        className={cn("w-full min-w-80", className)}
        data-tool-ui-id={id}
        data-slot="data-table"
      >
        <div className="hidden md:block">
          <div className="bg-card overflow-hidden rounded-lg border">
            <DataTableSkeleton columns={columns} />
          </div>
        </div>
        <div className="md:hidden">
          <MobileCardSkeleton />
        </div>
      </div>
    );
  }

  return (
    <div
      className={cn("w-full min-w-80", className)}
      data-tool-ui-id={id}
      data-slot="data-table"
      data-layout={layout}
    >
      {/* Desktop Table View */}
      <div
        className={cn(
          layout === "table"
            ? "block"
            : layout === "cards"
              ? "hidden"
              : "hidden md:block",
        )}
      >
        <div
          className={cn(
            "bg-card overflow-auto rounded-lg border",
            maxHeight && "max-h-[var(--max-height)]",
          )}
          style={
            maxHeight
              ? ({ "--max-height": maxHeight } as React.CSSProperties)
              : undefined
          }
        >
          <Table>
            <TableHeader>
              <TableRow>
                {columns.map((col) => (
                  <TableHead
                    key={col.key}
                    className={cn(getAlignmentClass(col.align))}
                    style={col.width ? { width: col.width } : undefined}
                  >
                    {col.sortable ? (
                      <Button
                        variant="ghost"
                        size="sm"
                        onClick={() => handleSort(col.key)}
                        className="h-auto p-0 font-medium hover:bg-transparent"
                      >
                        {col.label}
                        {renderSortIcon(col)}
                      </Button>
                    ) : (
                      col.label
                    )}
                  </TableHead>
                ))}
              </TableRow>
            </TableHeader>
            <TableBody>
              {data.length === 0 ? (
                <TableRow>
                  <TableCell
                    colSpan={columns.length}
                    className="text-muted-foreground py-8 text-center"
                  >
                    {emptyMessage}
                  </TableCell>
                </TableRow>
              ) : (
                data.map((row, index) => {
                  const rowId = String(row[rowIdKey] ?? index);
                  return (
                    <TableRow
                      key={rowId}
                      className="cursor-pointer hover:bg-muted/50"
                      onClick={() => handleRowClick(row)}
                    >
                      {columns.map((col) => (
                        <TableCell
                          key={col.key}
                          className={cn(getAlignmentClass(col.align))}
                        >
                          {formatCellValue(row[col.key])}
                        </TableCell>
                      ))}
                    </TableRow>
                  );
                })
              )}
            </TableBody>
          </Table>
        </div>
      </div>

      {/* Mobile Card View */}
      <div
        className={cn(
          layout === "cards"
            ? "block"
            : layout === "table"
              ? "hidden"
              : "md:hidden",
        )}
      >
        {data.length === 0 ? (
          <div className="text-muted-foreground py-8 text-center">
            {emptyMessage}
          </div>
        ) : (
          <Accordion type="single" collapsible className="space-y-2">
            {data.map((row, index) => {
              const rowId = String(row[rowIdKey] ?? index);
              const primaryCol = primaryColumns[0];
              const primaryValue = primaryCol
                ? formatCellValue(row[primaryCol.key])
                : rowId;

              return (
                <AccordionItem
                  key={rowId}
                  value={rowId}
                  className="bg-card rounded-lg border"
                >
                  <AccordionTrigger className="px-4 py-3 hover:no-underline">
                    <div className="flex flex-1 flex-col items-start gap-1 text-left">
                      <span className="font-medium">{primaryValue}</span>
                      {primaryColumns.slice(1).map((col) => (
                        <span
                          key={col.key}
                          className="text-muted-foreground text-sm"
                        >
                          {formatCellValue(row[col.key])}
                        </span>
                      ))}
                    </div>
                  </AccordionTrigger>
                  <AccordionContent className="px-4 pb-3">
                    <div className="space-y-2 pt-2">
                      {secondaryColumns.map((col) => (
                        <div
                          key={col.key}
                          className="flex justify-between gap-2"
                        >
                          <span className="text-muted-foreground text-sm">
                            {col.label}
                          </span>
                          <span className="text-sm font-medium">
                            {formatCellValue(row[col.key])}
                          </span>
                        </div>
                      ))}
                    </div>
                  </AccordionContent>
                </AccordionItem>
              );
            })}
          </Accordion>
        )}
      </div>

      {normalizedActions && (
        <div className="mt-3">
          <ActionButtons
            actions={normalizedActions.items}
            align={normalizedActions.align}
            confirmTimeout={normalizedActions.confirmTimeout}
            onAction={handleAction}
          />
        </div>
      )}
    </div>
  );
}
