# UI Prototyping Framework - Manual Verification Checklist

## WorkGrid Interface

- [ ] WorkGrid web UI loads and displays prototype cards correctly
- [ ] Clicking a card expands to full view with smooth animation
- [ ] Version history shows progression of AI iterations (can see old versions)

## Multi-Paradigm Rendering

- [ ] All 3 renderers (TUI, web, CLI) produce readable output from same ASCII
- [ ] Terminal aesthetic preserved in web renderer (feels like a terminal, not generic HTML)

## Data Integration & Hot Reload

- [ ] ASCII mockup with Superloop variables ({{iteration}}, {{test_status}}) renders with live data
- [ ] Dev server hot reload works (edit ASCII file → see update <1 sec)

## AI Collaboration Workflow

- [ ] README includes clear instructions for Claude Code to generate ASCII mockups
- [ ] Can successfully ask Claude Code: "Generate a TUI mockup for X" → Claude saves to correct location → renders appear

## Supergent Integration Readiness

- [ ] Package structure is compatible with Supergent monorepo layout (packages/ directory)
