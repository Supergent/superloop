/**
 * Tool UI Catalog Schemas
 *
 * Zod schemas for all 17 Tool UI components, adapted for the json-render catalog system.
 * These components provide conversation-native UI surfaces for AI tool outputs.
 */

import { createCatalog } from "@json-render/core";
import { z } from "zod";

// ===================
// Component Schemas
// ===================

export const toolUICatalog = createCatalog({
  components: {
    // ─────────────────────────────────────────────────────────────
    // 1. ApprovalCard - Binary confirmation for agent actions
    // ─────────────────────────────────────────────────────────────
    ApprovalCard: {
      props: z.object({
        id: z.string().optional().describe("Unique identifier"),
        title: z.string().describe("Action requiring approval"),
        description: z.string().optional().describe("Additional context"),
        icon: z.string().optional().describe("Lucide icon name (kebab-case)"),
        metadata: z
          .array(z.object({ key: z.string(), value: z.string() }))
          .optional()
          .describe("Key-value metadata to display"),
        variant: z.enum(["default", "destructive"]).default("default").describe("Visual variant"),
        confirmLabel: z.string().default("Approve").describe("Confirm button text"),
        cancelLabel: z.string().default("Deny").describe("Cancel button text"),
        decision: z.enum(["approved", "denied"]).optional().describe("Current decision state"),
        isLoading: z.boolean().optional().describe("Loading state"),
      }),
      description: "Binary confirmation card for agent actions requiring human approval",
    },

    // ─────────────────────────────────────────────────────────────
    // 2. Audio - Audio playback with artwork and metadata
    // ─────────────────────────────────────────────────────────────
    Audio: {
      props: z.object({
        src: z.string().describe("Audio file URL"),
        title: z.string().optional().describe("Track title"),
        artist: z.string().optional().describe("Artist name"),
        album: z.string().optional().describe("Album name"),
        artwork: z.string().optional().describe("Album artwork URL"),
        duration: z.number().optional().describe("Duration in seconds"),
      }),
      description: "Audio playback component with artwork and metadata display",
    },

    // ─────────────────────────────────────────────────────────────
    // 3. Chart - Interactive data visualization
    // ─────────────────────────────────────────────────────────────
    Chart: {
      props: z.object({
        type: z
          .enum(["line", "bar", "pie", "area", "scatter"])
          .describe("Chart type"),
        title: z.string().optional().describe("Chart title"),
        data: z
          .array(z.record(z.string(), z.union([z.string(), z.number(), z.null()])))
          .describe("Data points as array of objects"),
        xKey: z.string().optional().describe("Key for X axis values"),
        yKeys: z.array(z.string()).optional().describe("Keys for Y axis values"),
        colors: z.array(z.string()).optional().describe("Custom colors for series"),
        showLegend: z.boolean().default(true).describe("Show legend"),
        showGrid: z.boolean().default(true).describe("Show grid lines"),
        height: z.number().default(300).describe("Chart height in pixels"),
      }),
      description: "Interactive chart visualization for data display",
    },

    // ─────────────────────────────────────────────────────────────
    // 4. Citation - Source references with attribution
    // ─────────────────────────────────────────────────────────────
    Citation: {
      props: z.object({
        text: z.string().describe("Cited text or quote"),
        source: z.string().describe("Source name or title"),
        url: z.string().optional().describe("Source URL"),
        author: z.string().optional().describe("Author name"),
        date: z.string().optional().describe("Publication date"),
        pageNumber: z
          .union([z.string(), z.number()])
          .optional()
          .describe("Page reference"),
      }),
      description: "Source citation with attribution display",
    },

    // ─────────────────────────────────────────────────────────────
    // 5. CodeBlock - Syntax-highlighted code display
    // ─────────────────────────────────────────────────────────────
    CodeBlock: {
      props: z.object({
        id: z.string().optional().describe("Unique identifier"),
        code: z.string().describe("Code content"),
        language: z
          .string()
          .default("text")
          .describe("Programming language for syntax highlighting"),
        filename: z.string().optional().describe("Optional filename to display"),
        showLineNumbers: z.boolean().default(true).describe("Show line numbers"),
        highlightLines: z
          .array(z.number())
          .optional()
          .describe("Line numbers to highlight"),
        maxCollapsedLines: z
          .number()
          .optional()
          .describe("Max lines before collapse"),
        isLoading: z.boolean().optional().describe("Loading state"),
      }),
      description: "Syntax-highlighted code display with copy functionality",
    },

    // ─────────────────────────────────────────────────────────────
    // 6. DataTable - Sortable data table with mobile layout
    // ─────────────────────────────────────────────────────────────
    DataTable: {
      props: z.object({
        columns: z
          .array(
            z.object({
              key: z.string(),
              header: z.string(),
              sortable: z.boolean().optional(),
              width: z.string().optional(),
              align: z.enum(["left", "center", "right"]).optional(),
            }),
          )
          .describe("Column definitions"),
        data: z
          .array(z.record(z.string(), z.unknown()))
          .describe("Row data"),
        sortable: z.boolean().default(true).describe("Enable sorting"),
        pageSize: z.number().default(10).describe("Rows per page"),
        showPagination: z.boolean().default(true).describe("Show pagination controls"),
        emptyMessage: z.string().default("No data").describe("Message when empty"),
        rowAction: z.string().optional().describe("Action on row click"),
      }),
      description: "Data table with sorting, pagination, and mobile accordion layout",
    },

    // ─────────────────────────────────────────────────────────────
    // 7. Image - Images with metadata and attribution
    // ─────────────────────────────────────────────────────────────
    Image: {
      props: z.object({
        id: z.string().optional().describe("Unique identifier"),
        src: z.string().describe("Image URL"),
        alt: z.string().describe("Alt text for accessibility"),
        title: z.string().optional().describe("Image title"),
        href: z.string().optional().describe("Link URL when clicked"),
        domain: z.string().optional().describe("Source domain"),
        ratio: z
          .enum(["auto", "1:1", "4:3", "16:9", "3:2", "2:3", "9:16"])
          .default("auto")
          .describe("Aspect ratio"),
        fit: z
          .enum(["cover", "contain", "fill"])
          .default("cover")
          .describe("Object fit"),
        source: z
          .object({
            label: z.string().optional(),
            url: z.string().optional(),
            iconUrl: z.string().optional(),
          })
          .optional()
          .describe("Source attribution"),
        locale: z.string().optional().describe("Locale for formatting"),
        isLoading: z.boolean().optional().describe("Loading state"),
      }),
      description: "Image display with metadata and source attribution",
    },

    // ─────────────────────────────────────────────────────────────
    // 8. ImageGallery - Grid layout gallery
    // ─────────────────────────────────────────────────────────────
    ImageGallery: {
      props: z.object({
        images: z
          .array(
            z.object({
              src: z.string(),
              alt: z.string(),
              caption: z.string().optional(),
              thumbnail: z.string().optional(),
            }),
          )
          .describe("Gallery images"),
        columns: z
          .number()
          .min(1)
          .max(6)
          .default(3)
          .describe("Grid columns"),
        gap: z
          .enum(["none", "sm", "md", "lg"])
          .default("md")
          .describe("Gap between images"),
        lightbox: z.boolean().default(true).describe("Enable lightbox on click"),
      }),
      description: "Grid gallery for browsing image collections",
    },

    // ─────────────────────────────────────────────────────────────
    // 9. ItemCarousel - Horizontal carousel
    // ─────────────────────────────────────────────────────────────
    ItemCarousel: {
      props: z.object({
        items: z
          .array(
            z.object({
              id: z.string().optional(),
              title: z.string(),
              description: z.string().optional(),
              image: z.string().optional(),
              action: z.string().optional(),
            }),
          )
          .describe("Carousel items"),
        visibleItems: z
          .number()
          .min(1)
          .max(5)
          .default(3)
          .describe("Items visible at once"),
        showArrows: z.boolean().default(true).describe("Show navigation arrows"),
        showDots: z.boolean().default(true).describe("Show dot indicators"),
      }),
      description: "Horizontal carousel for browsing item collections",
    },

    // ─────────────────────────────────────────────────────────────
    // 10. LinkPreview - Rich link previews with OG data
    // ─────────────────────────────────────────────────────────────
    LinkPreview: {
      props: z.object({
        url: z.string().describe("URL to preview"),
        title: z.string().optional().describe("Override title"),
        description: z.string().optional().describe("Override description"),
        image: z.string().optional().describe("Override preview image"),
        siteName: z.string().optional().describe("Site name"),
        favicon: z.string().optional().describe("Site favicon URL"),
      }),
      description: "Rich link preview with Open Graph data",
    },

    // ─────────────────────────────────────────────────────────────
    // 11. OptionList - Single/multi-select choices
    // ─────────────────────────────────────────────────────────────
    OptionList: {
      props: z.object({
        options: z
          .array(
            z.object({
              id: z.string(),
              label: z.string(),
              description: z.string().optional(),
              disabled: z.boolean().optional(),
              icon: z.string().optional(),
            }),
          )
          .describe("Available options"),
        mode: z
          .enum(["single", "multi"])
          .default("single")
          .describe("Selection mode"),
        defaultSelected: z
          .array(z.string())
          .optional()
          .describe("Initially selected option IDs"),
        action: z.string().describe("Action to trigger on selection"),
        submitLabel: z
          .string()
          .optional()
          .describe("Submit button label for multi-select"),
        title: z.string().optional().describe("List title"),
      }),
      description: "Single or multi-select option list with response actions",
    },

    // ─────────────────────────────────────────────────────────────
    // 12. OrderSummary - Purchase confirmation with pricing
    // ─────────────────────────────────────────────────────────────
    OrderSummary: {
      props: z.object({
        items: z
          .array(
            z.object({
              name: z.string(),
              quantity: z.number(),
              price: z.number(),
              image: z.string().optional(),
            }),
          )
          .describe("Order line items"),
        subtotal: z.number().describe("Subtotal before tax/shipping"),
        tax: z.number().optional().describe("Tax amount"),
        shipping: z.number().optional().describe("Shipping cost"),
        discount: z.number().optional().describe("Discount amount"),
        total: z.number().describe("Final total"),
        currency: z.string().default("USD").describe("Currency code"),
        confirmAction: z.string().optional().describe("Action on confirm"),
        confirmLabel: z.string().default("Confirm Order").describe("Confirm button label"),
      }),
      description: "Itemized order/purchase summary with pricing breakdown",
    },

    // ─────────────────────────────────────────────────────────────
    // 13. ParameterSlider - Numeric adjustment controls
    // ─────────────────────────────────────────────────────────────
    ParameterSlider: {
      props: z.object({
        label: z.string().describe("Parameter label"),
        min: z.number().describe("Minimum value"),
        max: z.number().describe("Maximum value"),
        step: z.number().default(1).describe("Step increment"),
        defaultValue: z.number().optional().describe("Initial value"),
        unit: z.string().optional().describe("Unit suffix (e.g., 'px', '%')"),
        showValue: z.boolean().default(true).describe("Show current value"),
        action: z.string().describe("Action to trigger on change"),
      }),
      description: "Numeric parameter adjustment slider control",
    },

    // ─────────────────────────────────────────────────────────────
    // 14. Plan - Step-by-step task workflows
    // ─────────────────────────────────────────────────────────────
    Plan: {
      props: z.object({
        title: z.string().optional().describe("Plan title"),
        steps: z
          .array(
            z.object({
              id: z.string(),
              title: z.string(),
              description: z.string().optional(),
              status: z
                .enum(["pending", "in_progress", "complete", "failed", "skipped"])
                .default("pending"),
              substeps: z
                .array(
                  z.object({
                    id: z.string(),
                    title: z.string(),
                    status: z
                      .enum(["pending", "in_progress", "complete", "failed", "skipped"])
                      .default("pending"),
                  }),
                )
                .optional(),
            }),
          )
          .describe("Plan steps"),
        showProgress: z.boolean().default(true).describe("Show progress indicator"),
        collapsible: z.boolean().default(true).describe("Allow collapsing steps"),
      }),
      description: "Step-by-step task workflow visualization",
    },

    // ─────────────────────────────────────────────────────────────
    // 15. SocialPost - Social media renderers
    // ─────────────────────────────────────────────────────────────
    SocialPost: {
      props: z.object({
        platform: z
          .enum(["twitter", "instagram", "linkedin", "facebook"])
          .describe("Social platform"),
        author: z
          .object({
            name: z.string(),
            handle: z.string().optional(),
            avatar: z.string().optional(),
            verified: z.boolean().optional(),
          })
          .describe("Post author"),
        content: z.string().describe("Post text content"),
        media: z
          .array(
            z.object({
              type: z.enum(["image", "video"]),
              url: z.string(),
              alt: z.string().optional(),
            }),
          )
          .optional()
          .describe("Attached media"),
        metrics: z
          .object({
            likes: z.number().optional(),
            comments: z.number().optional(),
            shares: z.number().optional(),
            views: z.number().optional(),
          })
          .optional()
          .describe("Engagement metrics"),
        timestamp: z.string().optional().describe("Post timestamp"),
        url: z.string().optional().describe("Link to original post"),
      }),
      description: "Social media post renderer for X/Instagram/LinkedIn",
    },

    // ─────────────────────────────────────────────────────────────
    // 16. Terminal - Command-line output display
    // ─────────────────────────────────────────────────────────────
    Terminal: {
      props: z.object({
        id: z.string().optional().describe("Unique identifier"),
        command: z.string().describe("Command that was executed"),
        stdout: z.string().optional().describe("Standard output"),
        stderr: z.string().optional().describe("Standard error output"),
        exitCode: z.number().optional().describe("Exit code (0 = success)"),
        durationMs: z.number().optional().describe("Execution duration in ms"),
        cwd: z.string().optional().describe("Working directory"),
        truncated: z.boolean().optional().describe("Output was truncated"),
        maxCollapsedLines: z.number().optional().describe("Max lines before collapse"),
        isLoading: z.boolean().optional().describe("Loading state"),
      }),
      description: "Command-line terminal output display with ANSI support",
    },

    // ─────────────────────────────────────────────────────────────
    // 17. Video - Video playback with controls
    // ─────────────────────────────────────────────────────────────
    Video: {
      props: z.object({
        src: z.string().describe("Video URL or embed URL"),
        poster: z.string().optional().describe("Poster image URL"),
        title: z.string().optional().describe("Video title"),
        description: z.string().optional().describe("Video description"),
        aspectRatio: z
          .enum(["16:9", "4:3", "1:1", "9:16"])
          .default("16:9")
          .describe("Aspect ratio"),
        autoPlay: z.boolean().default(false).describe("Auto-play video"),
        muted: z.boolean().default(false).describe("Muted by default"),
        controls: z.boolean().default(true).describe("Show video controls"),
        loop: z.boolean().default(false).describe("Loop video"),
        provider: z
          .enum(["native", "youtube", "vimeo"])
          .default("native")
          .describe("Video provider"),
      }),
      description: "Video playback component with controls and poster support",
    },
  },

  // ===================
  // Actions
  // ===================
  actions: {
    approve: {
      description: "Approve an action",
      params: z.object({ id: z.string().optional() }),
    },
    reject: {
      description: "Reject an action",
      params: z.object({
        id: z.string().optional(),
        reason: z.string().optional(),
      }),
    },
    select_option: {
      description: "Select option(s) from a list",
      params: z.object({ selected: z.array(z.string()) }),
    },
    select_row: {
      description: "Select a row in a data table",
      params: z.object({ rowId: z.string() }),
    },
    play_media: {
      description: "Play audio/video",
      params: z.object({ id: z.string().optional() }),
    },
    pause_media: {
      description: "Pause audio/video",
      params: z.object({ id: z.string().optional() }),
    },
    set_parameter: {
      description: "Set parameter value from slider",
      params: z.object({ name: z.string(), value: z.number() }),
    },
    open_link: {
      description: "Open a link",
      params: z.object({ url: z.string() }),
    },
    copy_code: {
      description: "Copy code to clipboard",
      params: z.object({ code: z.string() }),
    },
    confirm_order: {
      description: "Confirm an order",
      params: z.object({ orderId: z.string().optional() }),
    },
    carousel_navigate: {
      description: "Navigate carousel",
      params: z.object({ direction: z.enum(["prev", "next"]), index: z.number().optional() }),
    },
    lightbox_open: {
      description: "Open image in lightbox",
      params: z.object({ index: z.number() }),
    },
    lightbox_close: {
      description: "Close lightbox",
      params: z.object({}),
    },
  },

  validation: "strict",
});

export type ToolUICatalog = typeof toolUICatalog;
