/**
 * Image - Image display with metadata and source attribution
 * Ported from: https://github.com/assistant-ui/tool-ui
 *
 * Adapted for json-render integration
 */

import * as React from "react";
import type { ComponentRenderProps } from "@json-render/react";
import { cn } from "../../lib/cn.js";
import {
  ActionButtons,
  normalizeActionsConfig,
  type ActionsProp,
} from "./shared/index.js";

const FALLBACK_LOCALE = "en-US";

interface Source {
  label?: string;
  url?: string;
  iconUrl?: string;
}

interface ImageProps {
  id?: string;
  src: string;
  alt: string;
  title?: string;
  href?: string;
  domain?: string;
  ratio?: "auto" | "1:1" | "4:3" | "16:9" | "3:2" | "2:3" | "9:16";
  fit?: "cover" | "contain" | "fill";
  source?: Source;
  locale?: string;
  responseActions?: ActionsProp;
  isLoading?: boolean;
  className?: string;
}

const RATIO_CLASS_MAP: Record<string, string> = {
  "1:1": "aspect-square",
  "4:3": "aspect-[4/3]",
  "16:9": "aspect-video",
  "3:2": "aspect-[3/2]",
  "2:3": "aspect-[2/3]",
  "9:16": "aspect-[9/16]",
};

function getFitClass(fit?: string): string {
  switch (fit) {
    case "contain":
      return "object-contain";
    case "fill":
      return "object-fill";
    case "cover":
    default:
      return "object-cover";
  }
}

function sanitizeHref(href?: string): string | undefined {
  if (!href) return undefined;
  try {
    const url = new URL(href);
    if (url.protocol === "http:" || url.protocol === "https:") {
      return href;
    }
    return undefined;
  } catch {
    return undefined;
  }
}

function ImageProgress() {
  return (
    <div className="flex w-full flex-col gap-3 p-5 animate-pulse">
      <div className="flex items-center gap-3 text-xs">
        <div className="bg-muted h-6 w-6 rounded-full" />
        <div className="bg-muted h-3 w-28 rounded" />
      </div>
      <div className="bg-muted h-40 w-full rounded-lg" />
      <div className="bg-muted h-4 w-3/4 rounded" />
    </div>
  );
}

interface SourceAttributionProps {
  source?: Source;
  sourceLabel?: string;
  fallbackInitial: string;
  hasClickableUrl: boolean;
  onSourceClick: (event: React.MouseEvent<HTMLButtonElement>) => void;
  title?: string;
}

function SourceAttribution({
  source,
  sourceLabel,
  fallbackInitial,
  hasClickableUrl,
  onSourceClick,
  title,
}: SourceAttributionProps) {
  const hasSource = Boolean(sourceLabel || source?.iconUrl);

  const content = (
    <div className="flex min-w-0 flex-1 items-center gap-3">
      {source?.iconUrl ? (
        <img
          src={source.iconUrl}
          alt=""
          aria-hidden="true"
          className="size-8 shrink-0 rounded-full object-cover"
          loading="lazy"
          decoding="async"
        />
      ) : fallbackInitial ? (
        <div className="bg-muted text-muted-foreground flex size-8 shrink-0 items-center justify-center rounded-full text-xs font-semibold uppercase">
          {fallbackInitial}
        </div>
      ) : null}
      <div className="min-w-0 flex-1">
        {title && (
          <div className="text-foreground line-clamp-1 text-sm font-medium">
            {title}
          </div>
        )}
        {sourceLabel && (
          <div className="text-muted-foreground line-clamp-1 text-xs">
            {sourceLabel}
          </div>
        )}
      </div>
    </div>
  );

  if (hasClickableUrl && hasSource) {
    return (
      <button
        type="button"
        onClick={onSourceClick}
        className="flex w-full items-center gap-3 text-left hover:opacity-80 focus-visible:ring-2 focus-visible:ring-ring focus-visible:outline-none"
      >
        {content}
      </button>
    );
  }

  return <div className="flex w-full items-center gap-3">{content}</div>;
}

export function Image({ element, onAction }: ComponentRenderProps) {
  const props = element.props as unknown as ImageProps;
  const {
    id,
    src,
    alt,
    title,
    href: rawHref,
    domain,
    ratio = "auto",
    fit = "cover",
    source,
    locale: providedLocale,
    responseActions,
    isLoading,
    className,
  } = props;

  const locale = providedLocale ?? FALLBACK_LOCALE;
  const sanitizedHref = sanitizeHref(rawHref);
  const resolvedSourceUrl = sanitizeHref(source?.url);

  const normalizedActions = React.useMemo(
    () => normalizeActionsConfig(responseActions),
    [responseActions],
  );

  const sourceLabel = source?.label ?? domain;
  const fallbackInitial = (sourceLabel ?? "").trim().charAt(0).toUpperCase();
  const hasSource = Boolean(sourceLabel || source?.iconUrl);

  const handleSourceClick = (event: React.MouseEvent<HTMLButtonElement>) => {
    event.preventDefault();
    event.stopPropagation();
    const targetUrl = resolvedSourceUrl ?? source?.url ?? sanitizedHref ?? src;
    if (!targetUrl) return;
    onAction?.({ name: "navigate", params: { url: targetUrl } });
  };

  const handleImageClick = () => {
    if (!sanitizedHref) return;
    onAction?.({ name: "navigate", params: { url: sanitizedHref } });
  };

  const handleResponseAction = React.useCallback(
    (actionId: string) => {
      onAction?.({ name: actionId });
    },
    [onAction],
  );

  const hasMetadata = title || hasSource;

  if (isLoading) {
    return (
      <article
        className={cn("relative w-full min-w-80 max-w-md", className)}
        aria-busy="true"
        data-tool-ui-id={id}
      >
        <div
          className={cn(
            "relative isolate flex w-full min-w-0 flex-col overflow-hidden rounded-xl",
            "border border-border bg-card text-sm shadow-sm",
          )}
        >
          <ImageProgress />
        </div>
      </article>
    );
  }

  return (
    <article
      className={cn("relative w-full min-w-80 max-w-md", className)}
      lang={locale}
      data-tool-ui-id={id}
      data-slot="image"
    >
      <div
        className={cn(
          "group relative isolate flex w-full min-w-0 flex-col overflow-hidden rounded-xl",
          "border border-border bg-card text-sm shadow-sm",
        )}
      >
        <div
          className={cn(
            "bg-muted group relative w-full overflow-hidden",
            ratio !== "auto" ? RATIO_CLASS_MAP[ratio] : "min-h-[160px]",
            sanitizedHref && "cursor-pointer",
          )}
          onClick={sanitizedHref ? handleImageClick : undefined}
          role={sanitizedHref ? "link" : undefined}
          tabIndex={sanitizedHref ? 0 : undefined}
          onKeyDown={
            sanitizedHref
              ? (e) => {
                  if (e.key === "Enter" || e.key === " ") {
                    e.preventDefault();
                    handleImageClick();
                  }
                }
              : undefined
          }
        >
          <img
            src={src}
            alt={alt}
            loading="lazy"
            decoding="async"
            className={cn(
              "absolute inset-0 h-full w-full",
              getFitClass(fit),
            )}
          />
        </div>
        {hasMetadata && (
          <div className="flex items-center gap-3 px-4 py-3">
            <SourceAttribution
              source={source}
              sourceLabel={sourceLabel}
              fallbackInitial={fallbackInitial}
              hasClickableUrl={Boolean(resolvedSourceUrl)}
              onSourceClick={handleSourceClick}
              title={title}
            />
          </div>
        )}
      </div>
      {normalizedActions && (
        <div className="mt-3">
          <ActionButtons
            actions={normalizedActions.items}
            align={normalizedActions.align}
            confirmTimeout={normalizedActions.confirmTimeout}
            onAction={handleResponseAction}
          />
        </div>
      )}
    </article>
  );
}
