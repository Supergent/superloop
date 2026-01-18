# @superloop/convex-scanner

Static security analysis tool for Convex backend code. Scans TypeScript functions in your Convex project to detect security issues and anti-patterns.

## Installation

```bash
npm install @superloop/convex-scanner
```

## Usage

### CLI

Run the scanner from the command line:

```bash
# Scan current directory
npx convex-scanner

# Scan specific project
npx convex-scanner ./my-project

# Output as JSON
npx convex-scanner --format json

# Save to file
npx convex-scanner --output report.md

# Custom Convex directory
npx convex-scanner --convex-dir ./backend
```

**CLI Options:**

- `--format, -f <format>` - Output format: `json` or `markdown` (default: `markdown`)
- `--config, -c <path>` - Path to config file (default: auto-discover)
- `--convex-dir, -d <path>` - Path to Convex directory (default: `./convex`)
- `--ignore <pattern>` - Ignore pattern (can be specified multiple times)
- `--rules <rule>` - Rule ID to enable (can be specified multiple times)
- `--output, -o <path>` - Output file path (default: stdout)
- `--help, -h` - Show help message

### Programmatic API

Use the scanner in your TypeScript/JavaScript code:

```typescript
import { scanConvex } from '@superloop/convex-scanner';

const result = await scanConvex('./my-project', {
  format: 'json',
  convexDir: './convex',
  throwOnError: false,
});

console.log(`Found ${result.findings.length} security issues`);
console.log(`Scanned ${result.scannedFiles.length} files`);

// Process findings
for (const finding of result.findings) {
  console.log(`${finding.severity}: ${finding.message}`);
  console.log(`  File: ${finding.file}:${finding.line}`);
  console.log(`  Remediation: ${finding.remediation}`);
}
```

**API Options:**

```typescript
interface ScanOptions {
  convexDir?: string | string[];       // Path(s) to Convex directory
  configPath?: string;                 // Configuration file path
  format?: 'json' | 'markdown';        // Output format
  rules?: Record<string, {             // Rule configuration overrides
    enabled?: boolean;
    severity?: FindingSeverity;
  }>;
  ignore?: string[];                   // Additional ignore patterns
  throwOnError?: boolean;              // Throw on errors (default: true)
}
```

## Configuration

Create a `convex-scanner.config.ts` file in your project root:

```typescript
export default {
  // Path to Convex directory (default: './convex')
  convexDir: './convex',

  // Files/directories to ignore
  ignore: [
    '**/node_modules/**',
    '**/_generated/**',
    '**/dist/**',
  ],

  // Rule configuration
  rules: {
    'auth/missing-auth-check': {
      enabled: true,
      severity: 'high',
    },
  },
};
```

**Default Ignore Patterns:**

The scanner ignores these patterns by default:
- `**/node_modules/**`
- `**/.git/**`
- `**/dist/**`
- `**/build/**`
- `**/_generated/**`

To include `_generated/` files, override the `ignore` pattern in your config.

## Output Formats

### JSON Format

Complete structured output with all findings, errors, and metadata:

```json
{
  "findings": [
    {
      "file": "convex/users.ts",
      "line": 12,
      "column": 0,
      "endLine": 15,
      "endColumn": 1,
      "rule": "auth/missing-auth-check",
      "category": "auth",
      "severity": "high",
      "message": "Mutation 'updateUser' does not check authentication",
      "remediation": "Add authentication check...",
      "context": "export const updateUser = mutation({\n  handler: async (ctx, args) => {\n    ..."
    }
  ],
  "scannedFiles": ["convex/users.ts", "convex/posts.ts"],
  "errors": [],
  "metadata": {
    "timestamp": "2025-01-17T10:30:00.000Z",
    "filesScanned": 2,
    "filesWithFindings": 1,
    "rulesRun": ["auth/missing-auth-check"],
    "scannerVersion": "0.1.0",
    "durationMs": 245
  }
}
```

### Markdown Format

Human-readable report with summary, findings grouped by severity, and remediation guidance:

```markdown
# Convex Security Scan Report

## Summary
- Scanner Version: 0.1.0
- Timestamp: 2025-01-17T10:30:00.000Z
- Duration: 245ms
- Files Scanned: 2
- Files with Findings: 1

## Rules Executed
- auth/missing-auth-check

## Findings by Severity

### High Severity (1)

#### convex/users.ts:12
- **Rule:** auth/missing-auth-check
- **Message:** Mutation 'updateUser' does not check authentication
- **Remediation:** Add authentication check: `const identity = await ctx.auth.getUserIdentity(); if (!identity) throw new Error('Unauthenticated');`
```

## Security Rules

### auth/missing-auth-check

**Category:** Authentication
**Severity:** High
**Description:** Detects mutations that don't check `ctx.auth` for authentication.

Mutations that modify data should verify user authentication before performing operations. This rule flags mutations that don't access `ctx.auth`.

**Exemptions:**
- `internalMutation` - Internal functions don't need auth checks

**Remediation:**
```typescript
export const updateUser = mutation({
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) {
      throw new Error('Unauthenticated');
    }
    // ... rest of mutation logic
  },
});
```

## Error Handling

By default, the scanner throws on configuration or discovery errors. Set `throwOnError: false` to collect errors instead:

```typescript
const result = await scanConvex('./my-project', {
  throwOnError: false,
});

if (result.errors.length > 0) {
  console.error('Scan errors:', result.errors);
}
```

## Performance

The scanner is designed to complete quickly:
- Typical project (~50 files): < 10 seconds
- Uses TypeScript Compiler API for accurate parsing
- Parallel file processing where possible

## Architecture

The scanner consists of:
- **Parser** - TypeScript AST analysis using Compiler API
- **Rule Engine** - Pluggable security rules
- **Config System** - Flexible configuration with sensible defaults
- **Output Formatters** - JSON and Markdown reports

## Development

```bash
# Build the package
npm run build

# Run tests
npm test

# Type checking
npm run typecheck

# Watch mode for development
npm run dev
```

## License

Apache-2.0
