---
name: superloop-view
description: |
  Generate custom dashboard views for the Superloop liquid interface.
  Use when user asks about loop status, wants to see specific data,
  or requests a custom visualization of superloop state.
  Triggers: "show me", "what's the status", "view", "dashboard",
  "superloop-view", "loop status", "how's the loop", "progress"
allowed-tools: Read, Grep, Glob, Bash, WebFetch
---

# Superloop View Generator

You generate custom dashboard views for Superloop's liquid interface using the json-render UITree format.

## Overview

The liquid dashboard automatically shows default views based on loop state. When users ask specific questions or want custom visualizations, you generate a UITree that overrides the default view.

## How It Works

1. User asks a question about the loop (e.g., "show me test failures")
2. You read relevant superloop state files
3. You generate a UITree targeting their question
4. You POST it to `/api/liquid/override`
5. The dashboard renders your custom view

---

# PART 1: UITree FORMAT

## Structure

A UITree is a flat structure with a root element and a map of elements:

```json
{
  "root": "main",
  "elements": {
    "main": {
      "type": "Stack",
      "props": { "gap": 16, "padding": 24 },
      "children": ["header", "content"]
    },
    "header": {
      "type": "Heading",
      "props": { "level": 1, "children": "My Dashboard" }
    },
    "content": {
      "type": "Text",
      "props": { "children": "Hello world" }
    }
  }
}
```

**Key rules**:
- `root` points to the top-level element key
- `elements` is a flat map (no nesting)
- `children` array contains element keys (strings), not objects
- Every element has `type` (component name) and `props` (component properties)

## Data Binding with DynamicValue

Use `{ "path": "/some/path" }` to bind data at runtime:

```json
{
  "type": "Text",
  "props": {
    "children": { "path": "/loop/phase" }
  }
}
```

The path references data in the context object. Common paths:
- `/loop/id` - Loop identifier
- `/loop/phase` - Current phase (planning, implementing, testing, reviewing)
- `/loop/iteration` - Current iteration number
- `/gates/tests` - Test status (passed, failed, pending)
- `/tasks` - Array of task items
- `/testFailures` - Array of test failures
- `/blockers` - Array of blockers
- `/cost` - Cost breakdown object

## Visibility Conditions

Control when elements render with `visibility`:

```json
{
  "type": "Alert",
  "props": { "variant": "error", "children": "Tests are failing!" },
  "visibility": {
    "conditions": [
      { "path": "/gates/tests", "op": "eq", "value": "failed" }
    ],
    "logic": "and"
  }
}
```

**Operators**: `eq`, `neq`, `gt`, `gte`, `lt`, `lte`, `in`, `nin`, `exists`, `nexists`, `contains`, `ncontains`

**Logic**: `and` (all must match), `or` (any must match)

---

# PART 2: AVAILABLE COMPONENTS

## Layout Components

### Stack
Vertical or horizontal layout container.
```json
{
  "type": "Stack",
  "props": {
    "direction": "column",  // "column" | "row"
    "gap": 16,              // spacing in pixels
    "padding": 24,          // padding in pixels
    "align": "stretch"      // "start" | "center" | "end" | "stretch"
  },
  "children": ["child1", "child2"]
}
```

### Grid
Grid layout for cards or items.
```json
{
  "type": "Grid",
  "props": {
    "columns": 3,           // number of columns
    "gap": 16
  },
  "children": ["item1", "item2", "item3"]
}
```

### Card
Container with border and background.
```json
{
  "type": "Card",
  "props": {
    "title": "Card Title",  // optional header
    "padding": 16
  },
  "children": ["content"]
}
```

### Divider
Horizontal separator line.
```json
{ "type": "Divider", "props": {} }
```

## Typography Components

### Heading
Section headers.
```json
{
  "type": "Heading",
  "props": {
    "level": 1,             // 1-4
    "children": "Title"     // text content (can be DynamicValue)
  }
}
```

### Text
Body text with optional styling.
```json
{
  "type": "Text",
  "props": {
    "variant": "body",      // "body" | "label" | "caption" | "mono"
    "color": "muted",       // "default" | "muted" | "success" | "warning" | "error"
    "children": "Content"
  }
}
```

## Status Components

### Badge
Inline status indicator.
```json
{
  "type": "Badge",
  "props": {
    "variant": "success",   // "default" | "success" | "warning" | "error" | "info"
    "children": "Passed"
  }
}
```

### Alert
Prominent status message.
```json
{
  "type": "Alert",
  "props": {
    "variant": "error",     // "info" | "success" | "warning" | "error"
    "title": "Error",       // optional
    "children": "Something went wrong"
  }
}
```

### ProgressBar
Visual progress indicator.
```json
{
  "type": "ProgressBar",
  "props": {
    "value": 75,            // 0-100 (can be DynamicValue)
    "label": "Progress"     // optional
  }
}
```

### EmptyState
Placeholder for no data.
```json
{
  "type": "EmptyState",
  "props": {
    "title": "No Data",
    "description": "Nothing to show yet"
  }
}
```

## Superloop-Specific Components

### GateStatus
Single gate indicator (tests, approval, etc.).
```json
{
  "type": "GateStatus",
  "props": {
    "name": "Tests",
    "status": { "path": "/gates/tests" }  // "passed" | "failed" | "pending" | "skipped"
  }
}
```

### GateSummary
All gates in one row.
```json
{
  "type": "GateSummary",
  "props": {
    "gates": { "path": "/gates" }
  }
}
```

### IterationHeader
Loop status header with phase and iteration.
```json
{
  "type": "IterationHeader",
  "props": {
    "loopId": { "path": "/loop/id" },
    "phase": { "path": "/loop/phase" },
    "iteration": { "path": "/loop/iteration" },
    "status": { "path": "/loop/status" }  // "running" | "complete" | "stuck" | "idle"
  }
}
```

### TaskList
Checklist of tasks from PHASE files.
```json
{
  "type": "TaskList",
  "props": {
    "tasks": { "path": "/tasks" },
    "title": "Current Tasks"
  }
}
```

Task item shape: `{ id: string, label: string, done: boolean, phase?: string }`

### TestFailures
List of failing tests with details.
```json
{
  "type": "TestFailures",
  "props": {
    "failures": { "path": "/testFailures" },
    "title": "Failing Tests"
  }
}
```

Failure shape: `{ name: string, message: string, file?: string, line?: number }`

### BlockerCard
Display a blocker with severity.
```json
{
  "type": "BlockerCard",
  "props": {
    "title": "Blocker Title",
    "description": "What's blocking progress",
    "severity": "high"      // "low" | "medium" | "high"
  }
}
```

### CostSummary
Token usage and cost breakdown.
```json
{
  "type": "CostSummary",
  "props": {
    "cost": { "path": "/cost" }
  }
}
```

Cost shape: `{ total: number, byRole: { planner: number, implementer: number, ... } }`

## Data Display Components

### KeyValue
Single key-value pair.
```json
{
  "type": "KeyValue",
  "props": {
    "label": "Status",
    "value": { "path": "/loop/phase" }
  }
}
```

### KeyValueList
Multiple key-value pairs.
```json
{
  "type": "KeyValueList",
  "props": {
    "items": [
      { "label": "Loop", "value": { "path": "/loop/id" } },
      { "label": "Phase", "value": { "path": "/loop/phase" } }
    ]
  }
}
```

## Interactive Components

### Button
Clickable action button.
```json
{
  "type": "Button",
  "props": {
    "children": "Approve",
    "variant": "primary",   // "primary" | "secondary" | "danger" | "ghost"
    "action": "approve_loop"
  }
}
```

### ActionBar
Group of action buttons.
```json
{
  "type": "ActionBar",
  "props": {
    "actions": [
      { "name": "approve_loop", "label": "Approve", "variant": "primary" },
      { "name": "reject_loop", "label": "Reject", "variant": "danger" }
    ]
  }
}
```

**Available actions**: `approve_loop`, `reject_loop`, `cancel_loop`, `view_artifact`, `view_logs`, `refresh`

## Tool UI Components

Rich display components for agent outputs. These are ported from [tool-ui](https://github.com/assistant-ui/tool-ui).

### ApprovalCard
Binary confirmation for agent actions.
```json
{
  "type": "ApprovalCard",
  "props": {
    "title": "Deploy to Production",
    "description": "This will deploy v2.1.0 to all servers",
    "approveLabel": "Deploy",
    "rejectLabel": "Cancel",
    "variant": "warning"
  }
}
```
Props: `title`, `description`, `approveLabel`, `rejectLabel`, `variant` ("default" | "warning" | "danger")

### CodeBlock
Syntax-highlighted code with Shiki.
```json
{
  "type": "CodeBlock",
  "props": {
    "code": "function hello() {\n  console.log('world');\n}",
    "language": "javascript",
    "title": "example.js",
    "showLineNumbers": true
  }
}
```
Props: `code`, `language`, `title`, `showLineNumbers`, `highlightLines`, `maxHeight`

### DataTable
Sortable table with mobile card layout.
```json
{
  "type": "DataTable",
  "props": {
    "columns": [
      { "key": "name", "label": "Name", "sortable": true },
      { "key": "status", "label": "Status" }
    ],
    "data": [
      { "id": "1", "name": "Task A", "status": "done" },
      { "id": "2", "name": "Task B", "status": "pending" }
    ],
    "defaultSort": { "by": "name", "direction": "asc" }
  }
}
```
Props: `columns`, `data`, `rowIdKey`, `layout` ("auto" | "table" | "cards"), `defaultSort`, `emptyMessage`

### Image
Responsive image with metadata.
```json
{
  "type": "Image",
  "props": {
    "src": "https://example.com/image.jpg",
    "alt": "Screenshot",
    "title": "App Screenshot",
    "caption": "Version 2.0 UI",
    "ratio": "16:9"
  }
}
```
Props: `src`, `alt`, `title`, `caption`, `ratio` ("auto" | "1:1" | "4:3" | "16:9" | "3:2"), `fit` ("cover" | "contain")

### LinkPreview
Rich link card with favicon and description.
```json
{
  "type": "LinkPreview",
  "props": {
    "href": "https://github.com/example/repo",
    "title": "Example Repository",
    "description": "A great open source project",
    "image": "https://example.com/og.jpg",
    "domain": "github.com",
    "favicon": "https://github.com/favicon.ico"
  }
}
```
Props: `href`, `title`, `description`, `image`, `domain`, `favicon`, `ratio`

### OptionList
Single or multi-select choices.
```json
{
  "type": "OptionList",
  "props": {
    "title": "Select a framework",
    "options": [
      { "id": "react", "label": "React", "description": "Popular UI library" },
      { "id": "vue", "label": "Vue", "description": "Progressive framework" }
    ],
    "mode": "single",
    "selectedIds": ["react"]
  }
}
```
Props: `title`, `options`, `mode` ("single" | "multi"), `selectedIds`, `disabled`

### Plan
Step-by-step workflow with expandable details.
```json
{
  "type": "Plan",
  "props": {
    "title": "Deployment Plan",
    "steps": [
      { "id": "1", "title": "Build", "status": "complete", "description": "npm run build" },
      { "id": "2", "title": "Test", "status": "in_progress", "description": "Running tests..." },
      { "id": "3", "title": "Deploy", "status": "pending" }
    ]
  }
}
```
Props: `title`, `steps` (array with id, title, status, description), `showProgress`

Step status values: `pending`, `in_progress`, `complete`, `skipped`, `failed`

### Terminal
Command-line output with ANSI color support.
```json
{
  "type": "Terminal",
  "props": {
    "title": "Build Output",
    "content": "$ npm run build\n\u001b[32mSuccess!\u001b[0m Built in 2.3s",
    "maxHeight": "300px"
  }
}
```
Props: `title`, `content`, `maxHeight`, `showCopy`

### Video
Video playback with controls.
```json
{
  "type": "Video",
  "props": {
    "src": "https://example.com/demo.mp4",
    "poster": "https://example.com/poster.jpg",
    "title": "Demo Video",
    "ratio": "16:9",
    "controls": true
  }
}
```
Props: `src`, `poster`, `title`, `ratio`, `autoPlay`, `muted`, `controls`, `loop`

---

# PART 3: READING SUPERLOOP STATE

## Key Files

Read these files from `.superloop/loops/<loop-id>/`:

| File | Content |
|------|---------|
| `state.json` | Current phase, iteration, runner info |
| `run-summary.json` | Overall status, gates, timing |
| `test-status.json` | Test results and failures |
| `events.jsonl` | Event log with usage/cost data |
| `tasks/PLAN.MD` | High-level plan |
| `tasks/PHASE_*.MD` | Task checklists with `[ ]` / `[x]` |

## Finding the Active Loop

```bash
# Check config for configured loops
cat .superloop/config.json | jq '.loops[].id'

# Find most recently active loop
ls -t .superloop/loops/ | head -1
```

## Parsing State

```bash
# Get current phase and iteration
cat .superloop/loops/<id>/state.json | jq '{phase: .phase, iteration: .iteration}'

# Get gate status
cat .superloop/loops/<id>/run-summary.json | jq '.gates'

# Get test failures
cat .superloop/loops/<id>/test-status.json | jq '.failures'
```

## Parsing Tasks from PHASE Files

Look for checkbox patterns:
- `- [ ] Task description` = unchecked
- `- [x] Task description` = checked

---

# PART 4: GENERATING THE VIEW

## Workflow

1. **Understand the question**: What does the user want to see?
2. **Read relevant state**: Get the data you need
3. **Design the UITree**: Choose components that answer the question
4. **Use data binding**: Connect to runtime data with `{ "path": "..." }`
5. **POST to override API**: Send the UITree to the dashboard

## Posting the Override

After generating your UITree, POST it:

```bash
SUPERLOOP_UI_BASE_URL="${SUPERLOOP_UI_BASE_URL:-${SUPERLOOP_UI_URL:-http://superloop-ui.localhost:1355}}"

curl -X POST "${SUPERLOOP_UI_BASE_URL}/api/liquid/override" \
  -H "Content-Type: application/json" \
  -d '{"root":"main","elements":{...}}'
```

Or if using WebFetch, make a POST request to the override endpoint.

## Saving as a Versioned View (Recommended)

To save the view with version history for future reference and iteration:

```bash
SUPERLOOP_UI_BASE_URL="${SUPERLOOP_UI_BASE_URL:-${SUPERLOOP_UI_URL:-http://superloop-ui.localhost:1355}}"

curl -X POST "${SUPERLOOP_UI_BASE_URL}/api/liquid/override" \
  -H "Content-Type: application/json" \
  -d '{
    "save": true,
    "viewName": "test-failures",
    "prompt": "Show me what tests are failing",
    "tree": {"root":"main","elements":{...}}
  }'
```

Or save directly to a named view:

```bash
SUPERLOOP_UI_BASE_URL="${SUPERLOOP_UI_BASE_URL:-${SUPERLOOP_UI_URL:-http://superloop-ui.localhost:1355}}"

curl -X POST "${SUPERLOOP_UI_BASE_URL}/api/liquid/views/test-failures" \
  -H "Content-Type: application/json" \
  -d '{
    "tree": {"root":"main","elements":{...}},
    "prompt": "Show me what tests are failing"
  }'
```

**Benefits of saving versions:**
- Track design evolution over time
- Roll back to previous versions
- See which prompt generated each view
- Build on previous iterations

## Clearing the Override

To return to default view:

```bash
SUPERLOOP_UI_BASE_URL="${SUPERLOOP_UI_BASE_URL:-${SUPERLOOP_UI_URL:-http://superloop-ui.localhost:1355}}"

curl -X DELETE "${SUPERLOOP_UI_BASE_URL}/api/liquid/override"
```

---

# PART 5: EXAMPLES

## Example 1: Test Failures Focus

User asks: "Show me what tests are failing"

```json
{
  "root": "main",
  "elements": {
    "main": {
      "type": "Stack",
      "props": { "gap": 16, "padding": 24 },
      "children": ["header", "summary", "failures"]
    },
    "header": {
      "type": "Heading",
      "props": { "level": 1, "children": "Test Failures" }
    },
    "summary": {
      "type": "Alert",
      "props": {
        "variant": "error",
        "children": "Tests are currently failing. See details below."
      },
      "visibility": {
        "conditions": [{ "path": "/gates/tests", "op": "eq", "value": "failed" }]
      }
    },
    "failures": {
      "type": "TestFailures",
      "props": {
        "failures": { "path": "/testFailures" },
        "title": "Failing Tests"
      }
    }
  }
}
```

## Example 2: Progress Overview

User asks: "How far along are we?"

```json
{
  "root": "main",
  "elements": {
    "main": {
      "type": "Stack",
      "props": { "gap": 24, "padding": 24 },
      "children": ["header", "status", "progress", "tasks"]
    },
    "header": {
      "type": "IterationHeader",
      "props": {
        "loopId": { "path": "/loop/id" },
        "phase": { "path": "/loop/phase" },
        "iteration": { "path": "/loop/iteration" },
        "status": { "path": "/loop/status" }
      }
    },
    "status": {
      "type": "GateSummary",
      "props": { "gates": { "path": "/gates" } }
    },
    "progress": {
      "type": "Card",
      "props": { "title": "Task Progress" },
      "children": ["progressBar"]
    },
    "progressBar": {
      "type": "ProgressBar",
      "props": {
        "value": { "path": "/taskProgress" },
        "label": "Tasks Completed"
      }
    },
    "tasks": {
      "type": "TaskList",
      "props": {
        "tasks": { "path": "/tasks" },
        "title": "Current Phase Tasks"
      }
    }
  }
}
```

## Example 3: Cost Analysis

User asks: "How much has this cost so far?"

```json
{
  "root": "main",
  "elements": {
    "main": {
      "type": "Stack",
      "props": { "gap": 16, "padding": 24 },
      "children": ["header", "summary", "breakdown"]
    },
    "header": {
      "type": "Heading",
      "props": { "level": 1, "children": "Cost Analysis" }
    },
    "summary": {
      "type": "KeyValueList",
      "props": {
        "items": [
          { "label": "Loop", "value": { "path": "/loop/id" } },
          { "label": "Iterations", "value": { "path": "/loop/iteration" } },
          { "label": "Current Phase", "value": { "path": "/loop/phase" } }
        ]
      }
    },
    "breakdown": {
      "type": "CostSummary",
      "props": { "cost": { "path": "/cost" } }
    }
  }
}
```

---

# PART 6: GUIDELINES

## Do's

- **Read state first**: Always check current loop state before generating
- **Use data binding**: Prefer `{ "path": "..." }` over hardcoded values
- **Keep it focused**: Answer the specific question, don't show everything
- **Use visibility conditions**: Show/hide based on actual state
- **Choose appropriate components**: Match component to data type

## Don'ts

- **Don't nest elements**: UITree is flat, use children arrays with keys
- **Don't hardcode data**: Use DynamicValue for live data
- **Don't forget to POST**: The view won't appear until you send it
- **Don't overcomplicate**: Simple views are better

## Component Selection Guide

| User Wants | Use Component |
|------------|---------------|
| See current status | IterationHeader + GateSummary |
| See test failures | TestFailures |
| See task progress | TaskList + ProgressBar |
| See cost | CostSummary |
| See blockers | BlockerCard (repeated) |
| Take action | ActionBar or Button |
| See key metrics | KeyValueList |
| Display code | CodeBlock |
| Show tabular data | DataTable |
| Preview a link | LinkPreview |
| Display images | Image |
| Show video | Video |
| Show command output | Terminal |
| Get user confirmation | ApprovalCard |
| Offer choices | OptionList |
| Show workflow steps | Plan |

---

# Remember

1. **Read before generating** - Always check loop state first
2. **UITree is flat** - No nested elements, use string keys in children
3. **Data binding** - Use `{ "path": "..." }` for live data
4. **POST the result** - Send to `/api/liquid/override`
5. **Match the question** - Focus on what user asked, not everything
