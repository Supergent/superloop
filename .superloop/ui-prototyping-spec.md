# Superloop UI Prototyping Framework

## Goal

Build a UI prototyping framework for Superloop that enables rapid experimentation across multiple UI paradigms (TUI, web, desktop, CLI) using AI-generated ASCII mockups as the universal design artifact. The framework provides a WorkGrid interface for managing prototypes, real-time rendering across paradigms, and live data binding to Superloop's execution state—all without modifying the core bash loop.

## Requirements

**Stack Alignment Requirements:**
- [ ] TypeScript 5.6+ codebase with strict mode
- [ ] Bun 1.2.18+ as package manager
- [ ] Biome for linting/formatting using Supergent's config
- [ ] Package structure compatible with Supergent monorepo (`packages/superloop-ui/`)
- [ ] Node >=20.0.0 runtime
- [ ] tsup for building (following supergent-cli pattern)
- [ ] React + Framer Motion for web-based WorkGrid UI

**AI-Generated Mockup Workflow:**
- [ ] Prompt documentation for Claude Code to generate quality ASCII mockups
- [ ] Storage system for AI-generated ASCII (versioned, timestamped in `.superloop/ui/prototypes/`)
- [ ] Command interface: `superloop-ui generate <view-name>` with natural language descriptions
- [ ] Regeneration/iteration support: `superloop-ui refine <view-name>` for AI refinements
- [ ] Variant comparison: multiple AI-generated versions viewable side-by-side

**Rendering Infrastructure:**
- [ ] ASCII → TUI renderer (blessed/ink/bubbletea)
- [ ] ASCII → Web renderer (HTML/CSS with terminal aesthetic)
- [ ] ASCII → CLI rich output (chalk/boxen)
- [ ] Real-time data binding (inject Superloop state variables into ASCII)

**WorkGrid Interface:**
- [ ] Card per prototype showing live preview and metadata
- [ ] Click card → expand to full view with renderer paradigm toggle
- [ ] Multi-paradigm toggle (view same ASCII as TUI/web/CLI simultaneously)
- [ ] Version history slider (navigate AI iteration progression)

**Superloop Integration:**
- [ ] Read `.superloop/loops/<id>/` artifacts (events.jsonl, run-summary.json, etc.)
- [ ] Live refresh when Superloop state changes
- [ ] No modifications to `superloop.sh` core (read-only access)

**Developer/User Experience:**
- [ ] Dev server with hot reload (`superloop-ui dev`)
- [ ] AI prompt guidance documentation (help Claude generate better ASCII)
- [ ] Git-friendly output (AI-generated ASCII is plain text, diffable)
- [ ] Export selected design → production code scaffold

## Constraints

**Runtime:**
- Node.js >=20.0.0
- Bun 1.2.18+ as package manager
- TypeScript 5.6+ (strict mode enabled)

**Superloop Integration:**
- Read-only access to `.superloop/` directory (no writes to state.json or artifacts)
- Must work with existing bash `superloop.sh` without modifications
- File-watching only (no process injection or IPC with running loops)

**AI Generation Model:**
- Human-in-the-loop with Claude Code (user must be in active session)
- Claude Code generates ASCII mockups via natural language prompts
- Framework provides save locations and file conventions
- No API automation, no CLI spawning - interactive collaboration only

**Rendering:**
- ASCII must be plain UTF-8 (no fancy Unicode box-drawing initially)
- Terminal size constraints (80x24 minimum, 120x40 reasonable max)
- Web rendering must preserve monospace/terminal aesthetic

**Future Supergent Integration:**
- Package structure: `packages/superloop-ui/` compatible
- No Convex dependency yet (use filesystem, upgrade later)
- Biome config must match Supergent's biome.json
- Cannot conflict with existing Supergent package names

**Performance:**
- Hot reload <100ms (for rapid iteration)
- WorkGrid must handle 20+ prototype cards
- ASCII → view compilation <50ms per renderer

**Dependencies:**
- Minimize external dependencies (easier future migration)
- Prefer Supergent-existing packages where possible

## Acceptance Criteria

**AI Collaboration Workflow:**
- [ ] User asks Claude Code to generate ASCII mockup → Claude saves to `.superloop/ui/prototypes/<name>.txt` → renders appear within 100ms
- [ ] User asks Claude to refine existing mockup → new version saved → WorkGrid shows both versions with timestamp
- [ ] Framework provides documentation that Claude Code can read to understand file structure and conventions

**Multi-Paradigm Rendering:**
- [ ] Same ASCII mockup renders in 3+ paradigms (TUI, web, CLI rich output)
- [ ] Web renderer preserves monospace terminal aesthetic (no breaking the illusion)
- [ ] TUI renderer runs in actual terminal without crashes
- [ ] Side-by-side comparison view works (see all 3 renderers at once)

**Superloop Data Integration:**
- [ ] ASCII mockup can reference variables like `{{iteration}}`, `{{test_status}}`, `{{promise}}`
- [ ] Framework reads `.superloop/loops/<id>/run-summary.json` and injects live data
- [ ] When Superloop state changes, rendered views update within 1 second

**WorkGrid Interface:**
- [ ] WorkGrid shows card for each prototype with live preview
- [ ] Click card → expands to full view with renderer toggle
- [ ] WorkGrid supports 20+ prototype cards without performance degradation
- [ ] Version history accessible (see AI iteration timeline)

**Developer Experience:**
- [ ] `superloop-ui dev` starts dev server and opens WorkGrid in browser
- [ ] File watcher detects new/modified ASCII files in <50ms
- [ ] All generated files are plain text and git-diffable
- [ ] Package structure allows drop-in to Supergent's `packages/` directory

**Supergent Alignment:**
- [ ] Code passes Biome checks using Supergent's biome.json config
- [ ] Builds successfully with `bun run build` using tsup
- [ ] CLI dependencies use Supergent versions: `chalk@^5.3.0`, `commander@^12.1.0`, `ora@^8.1.1`, `@inquirer/prompts@^7.2.0`
- [ ] Web dependencies match Supergent: `react@latest`, `framer-motion@latest`
- [ ] TypeScript `^5.6.0` or compatible

**Non-Breaking:**
- [ ] Does not modify `superloop.sh` or `.superloop/state.json`
- [ ] Runs standalone without requiring Supergent installation
- [ ] Can be removed completely without affecting Superloop operation

## Completion Promise

READY
