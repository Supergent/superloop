# Feature: Convex Security Scanner

## Overview

Build a TypeScript library (`packages/convex-scanner/`) that performs static security analysis of Convex backend code. The scanner parses Convex functions using the TypeScript Compiler API, understands Convex-specific patterns (queries, mutations, actions, ctx object, validators), and produces rich findings with remediation guidance. The architecture is designed to support future dynamic/URL-based scanning, though only static analysis is implemented in this iteration.

This is foundational infrastructure for security tooling - the parser and rule engine must be solid before expanding rule coverage.

## Requirements

### Package Structure

- [ ] REQ-1: Create `packages/convex-scanner/` as a new TypeScript package with `package.json`, `tsconfig.json`, and standard monorepo integration
- [ ] REQ-2: Use TypeScript Compiler API (`typescript` package) for AST parsing - no wrapper libraries
- [ ] REQ-3: Export a functional API: `scanConvex(projectPath: string, options?: ScanOptions): Promise<ScanResult>`
- [ ] REQ-4: Support configuration via `convex-scanner.config.ts` file in target project root

### Core Data Model

- [ ] REQ-5: Define `Finding` interface with: `file`, `line`, `column`, `endLine`, `endColumn`, `rule`, `category`, `severity`, `message`, `remediation`, `context` (surrounding code snippet)
- [ ] REQ-6: Define `category` as union type: `'auth' | 'validation' | 'exposure' | 'general'`
- [ ] REQ-7: Define `severity` as union type: `'critical' | 'high' | 'medium' | 'low' | 'info'`
- [ ] REQ-8: Define `ScanResult` interface with: `findings: Finding[]`, `scannedFiles: string[]`, `errors: ScanError[]`, `metadata: ScanMetadata`

### Convex Code Parser

- [ ] REQ-9: Implement `ConvexParser` class that uses TypeScript Compiler API to parse `.ts` and `.tsx` files
- [ ] REQ-10: Detect and classify Convex function types: `query`, `mutation`, `action`, `httpAction`, `internalQuery`, `internalMutation`, `internalAction`
- [ ] REQ-11: Extract function metadata: name, type, arguments schema, return type, file location
- [ ] REQ-12: Parse and understand `ctx` object usage patterns: `ctx.auth`, `ctx.db`, `ctx.storage`, `ctx.scheduler`
- [ ] REQ-13: Parse Convex schema definitions from `schema.ts` (tables, indexes, validators)
- [ ] REQ-14: Understand Convex validator patterns (`v.string()`, `v.object()`, etc.) in argument definitions

### Rule Engine

- [ ] REQ-15: Implement `Rule` interface with: `id`, `name`, `category`, `severity`, `description`, `check(context: RuleContext): Finding[]`
- [ ] REQ-16: Implement `RuleContext` providing access to: parsed function, AST node, full file AST, project-wide type information
- [ ] REQ-17: Create rule registry that loads and manages rules
- [ ] REQ-18: Support rule configuration (enable/disable, severity override) via config file

### MVP Rule: Missing Auth Check

- [ ] REQ-19: Implement `auth/missing-auth-check` rule that detects mutations without `ctx.auth` access
- [ ] REQ-20: Rule should have severity `high` by default
- [ ] REQ-21: Rule should provide remediation: "Add authentication check: `const identity = await ctx.auth.getUserIdentity(); if (!identity) throw new Error('Unauthenticated');`"
- [ ] REQ-22: Rule should NOT flag `internalMutation` (internal functions don't need auth checks)
- [ ] REQ-23: Rule should extract code context (3 lines before/after) for the finding

### Configuration System

- [ ] REQ-24: Define config file schema for `convex-scanner.config.ts`
- [ ] REQ-25: Config should support: `rules` (enable/disable/severity per rule), `ignore` (glob patterns for files/directories), `convexDir` (path to convex directory, default `./convex`)
- [ ] REQ-26: Default ignore patterns: `**/node_modules/**`, `**/.git/**`, `**/dist/**`, `**/build/**`, `**/_generated/**`
- [ ] REQ-27: `_generated/` should be ignored by default but configurable to include
- [ ] REQ-28: When no config file exists, use sensible defaults (all rules enabled, default ignores)

### Output Formats

- [ ] REQ-29: Implement JSON output format with full `ScanResult` structure
- [ ] REQ-30: Implement human-readable markdown report with: summary, findings grouped by severity, file-by-file breakdown
- [ ] REQ-31: Include scan metadata in output: timestamp, files scanned, rules run, scanner version

### File Discovery

- [ ] REQ-32: Implement file discovery that finds all `.ts`/`.tsx` files in the Convex directory
- [ ] REQ-33: Respect ignore patterns from config
- [ ] REQ-34: Handle monorepo structures (multiple convex directories)

## Technical Approach

### Key Files to Create

- `packages/convex-scanner/package.json` - Package manifest
- `packages/convex-scanner/tsconfig.json` - TypeScript config
- `packages/convex-scanner/src/index.ts` - Main entry point, exports `scanConvex`
- `packages/convex-scanner/src/parser/convex-parser.ts` - TypeScript AST parsing for Convex
- `packages/convex-scanner/src/parser/function-detector.ts` - Detect query/mutation/action patterns
- `packages/convex-scanner/src/parser/ctx-analyzer.ts` - Analyze ctx object usage
- `packages/convex-scanner/src/rules/rule.ts` - Rule interface and registry
- `packages/convex-scanner/src/rules/auth/missing-auth-check.ts` - MVP rule implementation
- `packages/convex-scanner/src/config/loader.ts` - Config file loading and validation
- `packages/convex-scanner/src/config/schema.ts` - Config schema definition
- `packages/convex-scanner/src/output/json.ts` - JSON formatter
- `packages/convex-scanner/src/output/markdown.ts` - Markdown report formatter
- `packages/convex-scanner/src/types.ts` - Shared type definitions

### Patterns to Follow

- Follow existing package patterns from `packages/json-render-core/` for structure
- Use Zod for config schema validation (already in monorepo)
- Use Vitest for testing (already configured)
- Export types alongside implementations

### Dependencies

- `typescript` - TypeScript Compiler API (core dependency)
- `zod` - Config validation (already in monorepo)
- `glob` or `fast-glob` - File discovery
- Dev: `vitest`, `@types/node`

### Architecture Notes

The scanner is designed with extensibility for dynamic scanning:

```
┌─────────────────────────────────────────────────────────┐
│                    scanConvex()                         │
│                 (main entry point)                      │
└─────────────────────┬───────────────────────────────────┘
                      │
          ┌───────────┴───────────┐
          ▼                       ▼
┌─────────────────────┐ ┌─────────────────────┐
│   StaticScanner     │ │   DynamicScanner    │
│   (implemented)     │ │   (future)          │
├─────────────────────┤ ├─────────────────────┤
│ - ConvexParser      │ │ - HTTP client       │
│ - AST analysis      │ │ - Endpoint probing  │
│ - Source code       │ │ - Auth testing      │
└─────────────────────┘ └─────────────────────┘
          │                       │
          └───────────┬───────────┘
                      ▼
          ┌─────────────────────┐
          │    Rule Engine      │
          │ (shared by both)    │
          └─────────────────────┘
                      │
                      ▼
          ┌─────────────────────┐
          │   Finding[]         │
          │ (unified output)    │
          └─────────────────────┘
```

## Acceptance Criteria

### Parser

- [ ] AC-1: When given a file with `export const myMutation = mutation({...})`, parser correctly identifies it as a mutation
- [ ] AC-2: When given a file with `export const myQuery = query({...})`, parser correctly identifies it as a query
- [ ] AC-3: When function uses `ctx.auth.getUserIdentity()`, parser detects auth usage
- [ ] AC-4: When function does NOT use `ctx.auth`, parser correctly reports no auth usage
- [ ] AC-5: When given `internalMutation`, parser correctly identifies it as internal

### Missing Auth Check Rule

- [ ] AC-6: When a mutation does not check `ctx.auth`, finding is generated with severity `high`
- [ ] AC-7: When a mutation DOES check `ctx.auth`, no finding is generated
- [ ] AC-8: When an `internalMutation` lacks auth check, no finding is generated (internal functions exempt)
- [ ] AC-9: Finding includes file path, line number, and code context

### Configuration

- [ ] AC-10: When `convex-scanner.config.ts` exists, settings are loaded and applied
- [ ] AC-11: When no config exists, scanner runs with sensible defaults
- [ ] AC-12: When a file matches ignore pattern, it is not scanned
- [ ] AC-13: When `_generated/` is explicitly included in config, it IS scanned

### Output

- [ ] AC-14: When `format: 'json'` specified, output is valid JSON matching `ScanResult` schema
- [ ] AC-15: When `format: 'markdown'` specified, output is readable markdown report
- [ ] AC-16: When findings exist, they include all required fields (file, line, rule, severity, message, remediation, context)

### Integration

- [ ] AC-17: `scanConvex('./packages/valet/convex')` successfully scans the existing Valet Convex code
- [ ] AC-18: Scanner completes without errors on valid Convex projects
- [ ] AC-19: Scanner returns meaningful errors for invalid paths or parse failures

## Constraints

- **Performance**: Scanning a typical Convex project (~50 files) should complete in under 10 seconds
- **Security**: Scanner reads files only, never executes or modifies code
- **Compatibility**: Must work with Convex 1.0+ function patterns
- **Dependencies**: Minimize external dependencies; prefer using what's already in monorepo

## Out of Scope

- Dynamic/URL-based scanning (architecture prepared, not implemented)
- LLM-assisted analysis (foundation laid, not implemented)
- IDE/editor integrations
- CI/CD integrations (scanner is a library, integrations built on top)
- Auto-fix/remediation application
- Rules beyond `missing-auth-check` (first rule only, more in future iterations)
- SARIF output format (JSON and markdown sufficient for MVP)
- Caching of parse results between runs

## Test Commands

```bash
# Run unit tests for convex-scanner package
cd packages/convex-scanner && npm test

# Type checking
cd packages/convex-scanner && npx tsc --noEmit

# Integration test: scan actual Convex code
cd packages/convex-scanner && npx tsx src/cli.ts ../valet/convex
```

## Open Questions for Planner

- Should the parser handle JavaScript files (`.js`) in addition to TypeScript, or is TypeScript-only acceptable?
- What's the best way to handle Convex's internal function references (e.g., `internal.myModule.myFunction`)?
- Should findings include a unique ID for deduplication across runs?

## Future Capabilities (Not This Iteration)

### Dynamic Scanning (Research Needed)

URL-based scanning that probes a running Convex backend:
- Discovery mechanism: Need to research Convex deployment introspection APIs
- Authentication context: Unauthenticated testing vs. authenticated with user tokens
- Probe types: Test actual auth enforcement, input validation, error handling

### Additional Rules (Future Iterations)

- `auth/insufficient-authorization` - Auth check exists but no role/permission verification
- `validation/unvalidated-args` - Arguments without validators
- `validation/weak-validator` - Validators that are too permissive (e.g., `v.any()`)
- `exposure/sensitive-fields` - Queries returning sensitive data (passwords, tokens, PII)
- `exposure/overfetching` - Queries returning more fields than needed
- `general/console-log` - Console statements in production code
