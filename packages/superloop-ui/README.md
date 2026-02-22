# Superloop UI

Superloop UI provides the web dashboard and component library for Superloop's **Liquid Interfaces** — contextual dashboards that adapt to loop state.

## Quick Start

```bash
cd ../..
scripts/dev-superloop-ui.sh
```

Access the dashboard at `http://superloop-ui.localhost:1355/liquid`.

Raw localhost fallback:

```bash
PORTLESS=0 bun run --cwd packages/superloop-ui dev -- --port 5173
```

## Architecture

Superloop UI is built on three layers:

```
┌─────────────────────────────────────────────────────┐
│                  Liquid Dashboard                    │
│         (React app at /liquid endpoint)             │
├─────────────────────────────────────────────────────┤
│              json-render Framework                   │
│   (UITree → React with Zod schemas & data binding)  │
├─────────────────────────────────────────────────────┤
│              Component Libraries                     │
│   ┌──────────────────┐  ┌──────────────────────┐   │
│   │ Superloop Catalog │  │  Tool UI Catalog    │   │
│   │ (~20 components)  │  │  (9 components)     │   │
│   └──────────────────┘  └──────────────────────┘   │
├─────────────────────────────────────────────────────┤
│              UI Primitives (shadcn/ui)              │
│        Tailwind CSS + Radix UI + Lucide Icons       │
└─────────────────────────────────────────────────────┘
```

## Component Catalogs

### Superloop Components

Domain-specific components for loop monitoring:

| Component | Description |
|-----------|-------------|
| `IterationHeader` | Loop status with phase and iteration |
| `GateStatus` | Single gate indicator |
| `GateSummary` | All gates in one row |
| `TaskList` | Checklist from PHASE files |
| `TestFailures` | Failing tests with details |
| `BlockerCard` | Blocker with severity |
| `CostSummary` | Token usage and cost breakdown |
| `ActionBar` | Approve/reject/cancel buttons |

### Tool UI Components

Rich display components ported from [assistant-ui/tool-ui](https://github.com/assistant-ui/tool-ui):

| Component | Description |
|-----------|-------------|
| `ApprovalCard` | Binary confirmation for agent actions |
| `CodeBlock` | Syntax-highlighted code (Shiki) |
| `DataTable` | Sortable table with mobile cards |
| `Image` | Responsive images with metadata |
| `LinkPreview` | Rich link cards |
| `OptionList` | Single/multi-select choices |
| `Plan` | Step-by-step workflows |
| `Terminal` | Command output with ANSI colors |
| `Video` | Video playback with controls |

### Layout & Typography

Shared components from both catalogs:

- **Layout**: `Stack`, `Grid`, `Card`, `Divider`
- **Typography**: `Heading`, `Text`, `Badge`, `Alert`
- **Data Display**: `KeyValue`, `KeyValueList`, `ProgressBar`
- **Interactive**: `Button`

## json-render UITrees

Views are defined as flat JSON structures:

```json
{
  "root": "main",
  "elements": {
    "main": {
      "type": "Stack",
      "props": { "gap": 16 },
      "children": ["header", "content"]
    },
    "header": {
      "type": "Heading",
      "props": { "level": 1, "children": "Dashboard" }
    },
    "content": {
      "type": "DataTable",
      "props": {
        "columns": [
          { "key": "name", "label": "Name", "sortable": true },
          { "key": "status", "label": "Status" }
        ],
        "data": [
          { "name": "Task 1", "status": "done" },
          { "name": "Task 2", "status": "pending" }
        ]
      }
    }
  }
}
```

### Data Binding

Use `{ "path": "/some/path" }` for runtime data:

```json
{
  "type": "Text",
  "props": {
    "children": { "path": "/loop/phase" }
  }
}
```

### Visibility Conditions

Control when elements render:

```json
{
  "type": "Alert",
  "props": { "variant": "error", "children": "Tests failing!" },
  "visibility": {
    "conditions": [{ "path": "/gates/tests", "op": "eq", "value": "failed" }]
  }
}
```

## Development

### Build

```bash
bun run build           # Full build (CSS + JS + assets)
bun run build:css       # Tailwind CSS only
bun run build:js        # TypeScript compilation
```

### Project Structure

```
src/
├── liquid/
│   ├── Dashboard.tsx       # Main dashboard component
│   ├── components/         # Superloop components
│   ├── tool-ui/            # Tool UI components
│   │   ├── shared/         # Action buttons, utilities
│   │   └── *.tsx           # Individual components
│   ├── superloop-catalog.ts
│   ├── tool-ui-catalog.ts
│   └── unified-catalog.ts
├── ui/                     # shadcn/ui primitives
├── lib/                    # Utilities (cn, etc.)
├── styles/
│   └── globals.css         # Tailwind + CSS variables
└── web/
    └── liquid.html         # HTML template
```

### Adding Components

1. Create component in `src/liquid/tool-ui/YourComponent.tsx`
2. Add to registry in `src/liquid/tool-ui/index.ts`
3. Add Zod schema to `src/liquid/tool-ui-catalog.ts`
4. Component will be available via `unifiedRegistry`

## API

### Override Endpoint

POST custom UITrees to replace the default view:

```bash
SUPERLOOP_UI_BASE_URL="${SUPERLOOP_UI_BASE_URL:-${SUPERLOOP_UI_URL:-http://superloop-ui.localhost:1355}}"

curl -X POST "${SUPERLOOP_UI_BASE_URL}/api/liquid/override" \
  -H "Content-Type: application/json" \
  -d '{"root":"main","elements":{...}}'
```

### Save Versioned View

```bash
SUPERLOOP_UI_BASE_URL="${SUPERLOOP_UI_BASE_URL:-${SUPERLOOP_UI_URL:-http://superloop-ui.localhost:1355}}"

curl -X POST "${SUPERLOOP_UI_BASE_URL}/api/liquid/views/my-view" \
  -H "Content-Type: application/json" \
  -d '{
    "tree": {"root":"main","elements":{...}},
    "prompt": "Show test failures"
  }'
```

### Clear Override

```bash
SUPERLOOP_UI_BASE_URL="${SUPERLOOP_UI_BASE_URL:-${SUPERLOOP_UI_URL:-http://superloop-ui.localhost:1355}}"

curl -X DELETE "${SUPERLOOP_UI_BASE_URL}/api/liquid/override"
```

## Exports

```typescript
// Component registries
import { unifiedRegistry, toolUIRegistry } from "superloop-ui";

// Catalogs for AI skill generation
import { unifiedCatalog, toolUICatalog, superloopCatalog } from "superloop-ui";

// Individual components
import { DataTable, CodeBlock, Terminal } from "superloop-ui/tool-ui";
```
