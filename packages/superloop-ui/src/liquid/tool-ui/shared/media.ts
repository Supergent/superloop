/**
 * Media Utilities
 * Ported from: https://github.com/assistant-ui/tool-ui
 */

export const RATIO_CLASS_MAP: Record<string, string> = {
  "1:1": "aspect-square",
  "4:3": "aspect-[4/3]",
  "16:9": "aspect-video",
  "3:2": "aspect-[3/2]",
  "2:3": "aspect-[2/3]",
  "9:16": "aspect-[9/16]",
  "5:3": "aspect-[5/3]",
};

export function getFitClass(fit?: string): string {
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

export function sanitizeHref(href?: string): string | undefined {
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
