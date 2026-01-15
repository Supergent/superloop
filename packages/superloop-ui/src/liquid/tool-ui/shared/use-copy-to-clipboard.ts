/**
 * useCopyToClipboard Hook
 * Ported from: https://github.com/assistant-ui/tool-ui
 */

import { useState, useCallback, useRef, useEffect } from "react";

function fallbackCopyToClipboard(text: string): boolean {
  if (typeof document === "undefined") return false;

  const textarea = document.createElement("textarea");
  textarea.value = text;
  textarea.style.position = "fixed";
  textarea.style.left = "-9999px";
  textarea.style.top = "-9999px";
  document.body.appendChild(textarea);
  textarea.focus();
  textarea.select();

  try {
    const successful = document.execCommand("copy");
    document.body.removeChild(textarea);
    return successful;
  } catch {
    document.body.removeChild(textarea);
    return false;
  }
}

export interface UseCopyToClipboardOptions {
  resetDelay?: number;
}

export interface UseCopyToClipboardReturn {
  copiedId: string | null;
  copy: (text: string, id?: string) => Promise<boolean>;
}

export function useCopyToClipboard(
  options: UseCopyToClipboardOptions = {},
): UseCopyToClipboardReturn {
  const { resetDelay = 2000 } = options;
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const timeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    return () => {
      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current);
      }
    };
  }, []);

  const copy = useCallback(
    async (text: string, id?: string): Promise<boolean> => {
      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current);
      }

      let success = false;

      if (typeof navigator !== "undefined" && navigator.clipboard?.writeText) {
        try {
          await navigator.clipboard.writeText(text);
          success = true;
        } catch {
          success = fallbackCopyToClipboard(text);
        }
      } else {
        success = fallbackCopyToClipboard(text);
      }

      if (success) {
        setCopiedId(id ?? "default");
        timeoutRef.current = setTimeout(() => {
          setCopiedId(null);
        }, resetDelay);
      }

      return success;
    },
    [resetDelay],
  );

  return { copiedId, copy };
}
