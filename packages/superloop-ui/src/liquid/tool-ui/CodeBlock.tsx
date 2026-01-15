/**
 * CodeBlock - Syntax-highlighted code display
 * Ported from: https://github.com/assistant-ui/tool-ui
 *
 * Adapted for json-render integration
 */

import { useMemo, useState, useCallback, useEffect } from "react";
import type { ComponentRenderProps } from "@json-render/react";
import { createHighlighter, type Highlighter } from "shiki";
import { Copy, Check, ChevronDown, ChevronUp } from "lucide-react";
import { cn } from "../../lib/cn.js";
import { Button } from "../../ui/button.js";
import { Collapsible, CollapsibleTrigger } from "../../ui/collapsible.js";
import {
  ActionButtons,
  normalizeActionsConfig,
  useCopyToClipboard,
  type ActionsProp,
} from "./shared/index.js";

interface CodeBlockProps {
  id?: string;
  code: string;
  language?: string;
  filename?: string;
  showLineNumbers?: boolean;
  highlightLines?: number[];
  maxCollapsedLines?: number;
  responseActions?: ActionsProp;
  isLoading?: boolean;
  className?: string;
}

const COPY_ID = "codeblock-code";

let highlighterPromise: Promise<Highlighter> | null = null;

function getHighlighter(): Promise<Highlighter> {
  if (!highlighterPromise) {
    highlighterPromise = createHighlighter({
      themes: ["github-dark", "github-light"],
      langs: [],
    });
  }
  return highlighterPromise;
}

const htmlCache = new Map<string, string>();

function getCacheKey(
  code: string,
  language: string,
  theme: string,
  showLineNumbers: boolean,
  highlightLines?: number[],
): string {
  return `${code}::${language}::${theme}::${showLineNumbers}::${highlightLines?.join(",") ?? ""}`;
}

const LANGUAGE_DISPLAY_NAMES: Record<string, string> = {
  typescript: "TypeScript",
  javascript: "JavaScript",
  python: "Python",
  tsx: "TSX",
  jsx: "JSX",
  json: "JSON",
  bash: "Bash",
  shell: "Shell",
  css: "CSS",
  html: "HTML",
  markdown: "Markdown",
  sql: "SQL",
  yaml: "YAML",
  go: "Go",
  rust: "Rust",
  text: "Plain Text",
};

function getLanguageDisplayName(lang: string): string {
  return LANGUAGE_DISPLAY_NAMES[lang.toLowerCase()] || lang.toUpperCase();
}

function getSystemTheme(): "light" | "dark" {
  if (typeof window === "undefined") return "dark";
  return window.matchMedia?.("(prefers-color-scheme: dark)").matches
    ? "dark"
    : "light";
}

function getDocumentTheme(): "light" | "dark" | null {
  if (typeof document === "undefined") return null;
  const root = document.documentElement;
  if (root.classList.contains("dark")) return "dark";
  if (root.classList.contains("light")) return "light";
  return null;
}

function useResolvedTheme(): "light" | "dark" {
  const [theme, setTheme] = useState<"light" | "dark">(() => {
    return getDocumentTheme() ?? getSystemTheme();
  });

  useEffect(() => {
    if (typeof window === "undefined" || typeof document === "undefined") {
      return;
    }

    const update = () => setTheme(getDocumentTheme() ?? getSystemTheme());

    const mql = window.matchMedia?.("(prefers-color-scheme: dark)");
    mql?.addEventListener("change", update);

    const observer = new MutationObserver(update);
    observer.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["class"],
    });

    return () => {
      mql?.removeEventListener("change", update);
      observer.disconnect();
    };
  }, []);

  return theme;
}

function CodeBlockProgress() {
  return (
    <div className="flex w-full animate-pulse flex-col gap-3 p-4">
      <div className="bg-muted h-4 w-3/4 rounded" />
      <div className="bg-muted h-4 w-1/2 rounded" />
      <div className="bg-muted h-4 w-2/3 rounded" />
    </div>
  );
}

export function CodeBlock({ element, onAction }: ComponentRenderProps) {
  const props = element.props as unknown as CodeBlockProps;
  const {
    id,
    code,
    language = "text",
    filename,
    showLineNumbers = true,
    highlightLines,
    maxCollapsedLines,
    responseActions,
    isLoading,
    className,
  } = props;

  const resolvedTheme = useResolvedTheme();
  const [isExpanded, setIsExpanded] = useState(false);
  const { copiedId, copy } = useCopyToClipboard();
  const isCopied = copiedId === COPY_ID;

  const theme = resolvedTheme === "dark" ? "github-dark" : "github-light";
  const cacheKey = getCacheKey(
    code,
    language,
    theme,
    showLineNumbers,
    highlightLines,
  );

  const [highlightedHtml, setHighlightedHtml] = useState<string | null>(
    () => htmlCache.get(cacheKey) ?? null,
  );

  useEffect(() => {
    const cached = htmlCache.get(cacheKey);
    if (cached) {
      setHighlightedHtml(cached);
      return;
    }

    let cancelled = false;

    async function highlight() {
      if (!code) {
        if (!cancelled) setHighlightedHtml("");
        return;
      }

      try {
        const highlighter = await getHighlighter();
        const loadedLangs = highlighter.getLoadedLanguages();

        if (!loadedLangs.includes(language)) {
          await highlighter.loadLanguage(
            language as Parameters<Highlighter["loadLanguage"]>[0],
          );
        }

        const lineCount = code.split("\n").length;
        const lineNumberWidth = `${String(lineCount).length + 0.5}ch`;

        const html = highlighter.codeToHtml(code, {
          lang: language,
          theme,
          transformers: [
            {
              line(node, line) {
                node.properties["data-line"] = line;
                if (highlightLines?.includes(line)) {
                  const highlightBg =
                    resolvedTheme === "dark"
                      ? "rgba(255,255,255,0.1)"
                      : "rgba(0,0,0,0.05)";
                  node.properties["style"] = `background:${highlightBg};`;
                }
                if (showLineNumbers) {
                  node.children.unshift({
                    type: "element",
                    tagName: "span",
                    properties: {
                      style: `display:inline-block;width:${lineNumberWidth};text-align:right;margin-right:1.5em;user-select:none;opacity:0.5;`,
                      "aria-hidden": "true",
                    },
                    children: [{ type: "text", value: String(line) }],
                  });
                }
              },
            },
          ],
        });
        if (!cancelled) {
          htmlCache.set(cacheKey, html);
          setHighlightedHtml(html);
        }
      } catch {
        const escaped = code
          .replace(/&/g, "&amp;")
          .replace(/</g, "&lt;")
          .replace(/>/g, "&gt;");
        if (!cancelled)
          setHighlightedHtml(`<pre><code>${escaped}</code></pre>`);
      }
    }
    void highlight();
    return () => {
      cancelled = true;
    };
  }, [
    cacheKey,
    code,
    language,
    theme,
    highlightLines,
    showLineNumbers,
    resolvedTheme,
  ]);

  const normalizedFooterActions = useMemo(
    () => normalizeActionsConfig(responseActions),
    [responseActions],
  );

  const lineCount = code.split("\n").length;
  const shouldCollapse = maxCollapsedLines && lineCount > maxCollapsedLines;
  const isCollapsed = shouldCollapse && !isExpanded;

  const handleCopy = useCallback(() => {
    copy(code, COPY_ID);
    onAction?.({ name: "copy_code", params: { code } });
  }, [code, copy, onAction]);

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
          <CodeBlockProgress />
        </div>
      </div>
    );
  }

  return (
    <div
      className={cn("flex w-full min-w-80 flex-col gap-3", className)}
      data-tool-ui-id={id}
      data-slot="code-block"
    >
      <div className="border-border bg-card overflow-hidden rounded-lg border shadow-sm">
        <div className="bg-card flex items-center justify-between border-b px-4 py-2">
          <div className="flex items-center gap-1">
            <span className="text-muted-foreground text-sm">
              {getLanguageDisplayName(language)}
            </span>
            {filename && (
              <>
                <span className="text-muted-foreground/50">•</span>
                <span className="text-foreground text-sm font-medium">
                  {filename}
                </span>
              </>
            )}
          </div>
          <Button
            variant="ghost"
            size="sm"
            onClick={handleCopy}
            className="h-7 w-7 p-0"
            aria-label={isCopied ? "Copied" : "Copy code"}
          >
            {isCopied ? (
              <Check className="h-4 w-4 text-green-400" />
            ) : (
              <Copy className="text-muted-foreground h-4 w-4" />
            )}
          </Button>
        </div>

        <Collapsible open={!isCollapsed}>
          <div
            className={cn(
              "overflow-x-auto overflow-y-clip text-sm [&_pre]:bg-transparent [&_pre]:py-4",
              isCollapsed && "max-h-[200px]",
            )}
          >
            {highlightedHtml && (
              <div dangerouslySetInnerHTML={{ __html: highlightedHtml }} />
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
                    <ChevronUp className="mr-2 h-4 w-4" />
                    Collapse
                  </>
                )}
              </Button>
            </CollapsibleTrigger>
          )}
        </Collapsible>
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
