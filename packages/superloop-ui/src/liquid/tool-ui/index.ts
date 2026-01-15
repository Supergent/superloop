/**
 * Tool UI Components Registry
 * Ported from: https://github.com/assistant-ui/tool-ui
 *
 * Components adapted for json-render integration
 */

import type { ComponentRegistry } from "@json-render/react";
import { ApprovalCard } from "./ApprovalCard.js";
import { CodeBlock } from "./CodeBlock.js";
import { DataTable } from "./DataTable.js";
import { Image } from "./Image.js";
import { LinkPreview } from "./LinkPreview.js";
import { OptionList } from "./OptionList.js";
import { Plan } from "./Plan.js";
import { Terminal } from "./Terminal.js";
import { Video } from "./Video.js";

// Export individual components
export { ApprovalCard } from "./ApprovalCard.js";
export { CodeBlock } from "./CodeBlock.js";
export { DataTable } from "./DataTable.js";
export { Image } from "./Image.js";
export { LinkPreview } from "./LinkPreview.js";
export { OptionList } from "./OptionList.js";
export { Plan } from "./Plan.js";
export { Terminal } from "./Terminal.js";
export { Video } from "./Video.js";

// Export shared utilities
export * from "./shared/index.js";

/**
 * Tool UI Component Registry for json-render
 */
export const toolUIRegistry: ComponentRegistry = {
  ApprovalCard,
  CodeBlock,
  DataTable,
  Image,
  LinkPreview,
  OptionList,
  Plan,
  Terminal,
  Video,
};

/**
 * List of available Tool UI component types
 */
export const toolUIComponentTypes = [
  "ApprovalCard",
  "CodeBlock",
  "DataTable",
  "Image",
  "LinkPreview",
  "OptionList",
  "Plan",
  "Terminal",
  "Video",
] as const;

export type ToolUIComponentType = (typeof toolUIComponentTypes)[number];
