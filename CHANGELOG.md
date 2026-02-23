# Changelog

## 0.6.2 - 2026-02-23

### Added
- **Horizon control-plane contract**: Added `docs/horizon-planning.md` and `schema/horizons.schema.json` to define optional horizon planning above Superloop loops.
- **Horizon example artifact**: Added `docs/examples/horizons.example.json` to show practical horizon/slice linkage.
- **Horizon validator script**: Added `scripts/validate-horizons.sh` for reusable horizon control-plane validation (base schema checks + invariant checks, with optional strict JSON Schema mode).

### Changed
- **Loop schema linkage**: Added optional `loops[].horizon_ref` in `schema/config.schema.json` to bind a loop to a horizon when needed.
- **Constructor guidance**: Updated `construct-superloop` skill to support optional horizon-aware authoring and verification while keeping non-horizon loops valid.
- **Docs and handoff verification**: Replaced ad-hoc horizon `jq` checks in guidance with `scripts/validate-horizons.sh` for a single validation path.

## 0.6.1 - 2026-02-20

### Changed
- **construct-superloop skill guidance**: Added tighter loop-id derivation and explicit dry-run validation flow with non-dry-run delegation checks.
- **Delegation docs alignment**: Documented delegation wave/parallel behavior and adaptation semantics updates in skill guidance.

### Fixed
- **E2E pricing fallback assertion**: Updated unknown-model fallback test to match current pricing schema key (`input`).
- **Runner test portability**: Removed hard dependency on `bc` and stabilized no-python warning assertion to avoid pipeline/SIGPIPE flake.

## 0.6.0 - 2026-02-20

### Added
- **Role-local delegation orchestration**: Parent roles can execute delegated child work with persisted request, per-wave status, and summary artifacts.
- **Delegation request pass for implementer**: Live runs now support request-generation and execution flow in the same iteration.
- **Delegation event/usage visibility**: Child lifecycle and adaptation decisions are captured in events and child usage artifacts.

### Changed
- **Wave dispatch behavior**: `dispatch_mode: "parallel"` executes sibling children concurrently inside each wave.
- **Adaptive wake-policy hardening**: `on_child_complete` is normalized to `on_wave_complete` for parallel waves with explicit adaptation metadata.
- **Failure/retry handling**: Delegated-child retries and failure-policy outcomes are enforced with clearer status accounting.
- **Validation compatibility**: Legacy and explicit wake labels are normalized consistently in static/runtime validation paths.

## 0.5.1 - 2026-01-14

### Added
- **Tool UI component library**: 9 components ported from [tool-ui](https://github.com/assistant-ui/tool-ui)
  - ApprovalCard: Binary confirmation for agent actions
  - CodeBlock: Syntax-highlighted code with line numbers and copy button (powered by Shiki)
  - DataTable: Sortable columns with mobile accordion layout
  - Image: Responsive images with aspect ratios and metadata
  - LinkPreview: Rich link cards with favicon and description
  - OptionList: Single/multi-select choices with keyboard navigation
  - Plan: Step-by-step workflows with expandable details
  - Terminal: Command-line output with ANSI color support
  - Video: Video playback with controls and poster images
- **Tailwind CSS infrastructure**: Native Tailwind styling for all components
  - CSS variable theming matching existing design tokens
  - Dark mode by default
  - PostCSS build pipeline
- **shadcn/ui primitives**: Button, Card, Badge, Accordion, Table, Tooltip, and more
- **Unified component registry**: `unifiedRegistry` merges Superloop + Tool UI components
  - `toolUICatalog` with Zod schemas for all Tool UI components
  - `unifiedCatalog` combines both catalogs for AI skill generation

## 0.5.0 - 2026-01-14

### Added
- **Liquid interfaces**: Contextual dashboard that adapts to loop state
  - Default views auto-select based on phase (idle, progress, approval, stuck, complete)
  - Gate status, task progress, cost tracking in real-time
  - Access at `http://localhost:3333/liquid` when running dev server
- **`/superloop-view` skill**: Generate custom dashboard views via natural language
  - "Show me test failures" → AI generates focused UITree
  - POSTs to `/api/liquid/override` to replace default view
- **json-render packages**: Generative UI framework with guardrails
  - `@json-render/core`: Catalog (Zod schemas), UITree structure, data binding, visibility conditions, actions
  - `@json-render/react`: React renderer with context providers
  - `generateSkillPrompt()`: Auto-generate documentation from catalogs for AI skills
- **Superloop component catalog**: ~20 components for loop monitoring
  - Layout: Stack, Grid, Card, Divider
  - Status: GateStatus, GateSummary, IterationHeader, Badge, Alert, ProgressBar
  - Data: TaskList, TestFailures, BlockerCard, CostSummary, KeyValue, KeyValueList
  - Actions: Button, ActionBar (approve, reject, cancel, view logs)

### Changed
- Updated directory structure: `packages/` now contains json-render-core, json-render-react, superloop-ui
- ARCHITECTURE.md: Added "Why Liquid Interfaces?" section

## 0.4.1 - 2026-01-14

### Added
- **Per-role model configuration**: Specify model per role (e.g., `gpt-5.2-codex`, `claude-sonnet-4-5-20250929`)
- **Thinking level abstraction**: Unified `thinking` field (`none`|`minimal`|`low`|`standard`|`high`|`max`)
  - Codex: maps to `-c model_reasoning_effort` (none → xhigh)
  - Claude: maps to `MAX_THINKING_TOKENS` env var (0 → 32000 per request)
- **Basic test suite**: 13 bats tests covering version, validate, list, status, init, dry-run
- **Role defaults**: Top-level `role_defaults` for global model/thinking configuration
- **Improved token tracking**: Now captures reasoning/thinking tokens for accurate cost tracking
  - Claude: `thinking_tokens` (billed separately from output_tokens)
  - Codex: `reasoning_output_tokens`, `cached_input_tokens`
- **Cost calculation**: Automatic USD cost per role based on model pricing
  - Pricing table for Claude (Opus/Sonnet/Haiku 4.5, 4.x) and Codex (gpt-5.x)
  - Includes cache read/write pricing differentials
  - Each usage event now includes `cost_usd` field
- **Usage command**: `superloop.sh usage --loop ID` shows token/cost summary
  - Aggregates input, output, thinking/reasoning, and cache tokens
  - Shows cost breakdown by role (planner, implementer, tester, reviewer)
  - Shows cost breakdown by runner (claude, codex)
  - `--json` flag for machine-readable output
- **HTML report usage section**: Report now includes Usage & Cost section
  - Summary stats (total cost, duration, iterations)
  - Token breakdown table
  - Cost by role and runner tables
- **Constructor model selection**: Handoff phase now configures model and thinking per role

### Changed
- Default role configuration:
  - Planner: Codex gpt-5.2-codex, thinking=max
  - Implementer: Claude claude-sonnet-4-5-20250929, thinking=standard
  - Tester: Claude claude-sonnet-4-5-20250929, thinking=standard
  - Reviewer: Codex gpt-5.2-codex, thinking=max

## 0.4.0 - 2026-01-14

### Added
- **Spec-driven testing**: Tester verifies AC coverage (each acceptance criterion has a test)
- **ARCHITECTURE.md**: Documents design rationale (why separate roles, gates, phases, etc.)

### Changed
- **Repository cleanup**: Removed 17,000+ lines of cruft
  - Deleted `tools/claude-code-glm/` (21 markdown files, benchmark tooling)
  - Deleted `benchmarks/` directory and results
  - Deleted `prose/` submodule (OpenProse integration)
  - Deleted `feat/` directory (stale feature work)
  - Deleted redundant spec-authoring system (`.superloop/skills/`, `plan-session.sh`)
  - Deleted stale docs (`GETTING_STARTED.md`, `OPENPROSE_INTEGRATION.md`, `PRODUCTIZATION_PHASE_1.MD`)
  - Cleaned `.superloop/config.json` (removed completed loops)
- **README rewrite**: Clear architecture diagram, accurate documentation

### Removed
- OpenProse integration (`prose-author` and `openprose` roles)
- Runner-agnostic spec authoring (consolidated to Claude Code skill)
- Benchmark framework and results

## 0.3.1 - 2026-01-13

### Added
- Pre-flight usage check with configurable thresholds (warn at 70%, block at 95%)
- Rate limit handling with automatic pause and 100% resume reliability
- Per-role runner selection for multi-model orchestration
- `list` command to show configured loops and their status

### Changed
- Usage check enabled by default in schema

## 0.3.0 - 2026-01-05

### Changed
- Rename main wrapper script to `superloop.sh` (breaking change)

## 0.2.0 - 2026-01-05

### Changed
- Replace codex-specific config with generic runner abstraction (breaking config change)
- Add placeholder expansion for runner arguments and prompt mode selection
- Split wrapper into `src/` modules with build script (single-file output preserved)
- Rename branding to Supergent

## 0.1.5 - 2026-01-05

### Fixed
- Approval decision updates no longer blank `approval.json` with empty notes

## 0.1.4 - 2026-01-05

### Added
- Per-role timeout support to prevent hanging runs
- Reviewer packet generation to reduce reviewer context load

## 0.1.3 - 2026-01-05

### Added
- Optional approval gating with `approve` command and decision logs
- Approval/decision artifacts in run summaries and reports

## 0.1.2 - 2026-01-05

### Added
- `status --summary` for gate/evidence snapshot from run summaries
- CI report generation and `report.html` artifact upload

## 0.1.1 - 2026-01-05

### Added
- Observability artifacts (events, run summary, timeline)
- `report` command to generate HTML loop reports
- Evidence manifests with artifact hashes/mtimes and gate file metadata

## 0.1.0 - 2026-01-05

### Added
- `--version` flag and version output
- Config schema and `validate` command
- CI workflow for validation and dry-run smoke check
- MIT license
