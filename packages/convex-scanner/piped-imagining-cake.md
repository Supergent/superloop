# Enhancement Plan: Convex-Scanner Authentication Rules

## Overview
Enhance the `auth/missing-auth-check` rule to address two critical limitations:
1. **Expand coverage**: Check queries, actions, and httpAction, not just mutations
2. **Add suppression support**: Allow intentionally public functions via inline comments and allowlist patterns

## Approach
Hybrid solution combining:
- Extended rule checking all function types (queries, mutations, actions, httpAction)
- Inline comment suppressions (`// @convex-scanner allow-unauthenticated`)
- Configuration-based allowlists (glob patterns like `signup*`, `login`)
- **Default behavior**: Check all function types (queries, mutations, actions, httpAction)
- `checkActions` controls both `action` and `httpAction`.

## Critical Files

### Files to Modify
- `src/config/schema.ts` - Add `options` field to `ruleConfigSchema`
- `src/config/defaults.ts` - Add default options for auth rule
- `src/rules/rule.ts` - Add `options` and `config` to `RuleConfiguration` and `RuleContext`
- `src/rules/registry.ts` - Persist and merge rule `options` when applying config
- `src/rules/auth/missing-auth-check.ts` - Enhance with query/action checking and suppression logic
- `src/scanner/static-scanner.ts` - Pass rule config to `RuleContext`
- `src/parser/function-detector.ts` - Treat `httpAction` as an action for auth checks
- `packages/convex-scanner/package.json` - Add `minimatch` dependency

### Files to Create
- `src/parser/comment-analyzer.ts` - Parse TypeScript comments for suppression directives
- `src/utils/pattern-matcher.ts` - Glob pattern matching for allowlists
- `src/parser/__tests__/comment-analyzer.test.ts` - Tests for comment parser
- `src/utils/__tests__/pattern-matcher.test.ts` - Tests for pattern matcher
- `src/__tests__/fixtures/convex/query-no-auth.ts` - Test fixture
- `src/__tests__/fixtures/convex/action-no-auth.ts` - Test fixture
- `src/__tests__/fixtures/convex/action-with-auth.ts` - Test fixture
- `src/__tests__/fixtures/convex/http-action-no-auth.ts` - Test fixture
- `src/__tests__/fixtures/convex/mutation-with-suppression.ts` - Test fixture

### Files to Update (Tests)
- `src/rules/auth/__tests__/missing-auth-check.test.ts` - Add test cases for new functionality

## Implementation Steps

### 1. Add Dependencies
```json
// package.json
{
  "dependencies": {
    "minimatch": "^9.0.3"
  }
}
```
`minimatch` ships its own types; no `@types/minimatch` needed.

### 2. Extend Configuration Schema
```typescript
// src/config/schema.ts
export const ruleConfigSchema = z.object({
  enabled: z.boolean().optional(),
  severity: z.enum(['critical', 'high', 'medium', 'low', 'info']).optional(),
  options: z.object({
    checkQueries: z.boolean().optional().default(true),
    checkMutations: z.boolean().optional().default(true),
    checkActions: z.boolean().optional().default(true),
    allowList: z.array(z.string()).optional().default([]),
    allowInlineSuppressions: z.boolean().optional().default(true),
  }).optional(),
});
```

### 3. Update Type Definitions
```typescript
// src/rules/rule.ts
export interface RuleConfiguration {
  enabled: boolean;
  severity: FindingSeverity;
  options?: Record<string, unknown>;
}

export interface RuleContext {
  function: ConvexFunction;
  typeChecker: ts.TypeChecker;
  program: ts.Program;
  config?: RuleConfiguration;  // Add config
}
```

### 4. Create Comment Analyzer Utility
```typescript
// src/parser/comment-analyzer.ts
export function hasSuppression(node: ts.Node, directive: string): boolean;
export function extractSuppressions(node: ts.Node): string[];
export function getLeadingComments(node: ts.Node, sourceFile: ts.SourceFile): string[];
```

Implementation details:
- Use TypeScript's `getLeadingCommentRanges()` API
- When checking a variable declaration, also look at its parent `VariableStatement`
- Parse for `@convex-scanner allow-unauthenticated` directive (case-insensitive)
- Support both `//` and `/* */` comment styles

### 5. Create Pattern Matcher Utility
```typescript
// src/utils/pattern-matcher.ts
import { minimatch } from 'minimatch';

export function matchesPattern(functionName: string, patterns: string[]): boolean {
  return patterns.some(pattern => minimatch(functionName, pattern, { nocase: true }));
}
```

### 6. Enhance Missing Auth Check Rule
```typescript
// src/rules/auth/missing-auth-check.ts

check(context: RuleContext): Finding[] {
  const { function: func, config } = context;

  // Extract options with defaults
  const options = {
    checkQueries: true,
    checkMutations: true,
    checkActions: true,
    allowList: [],
    allowInlineSuppressions: true,
    ...(config?.options || {}),
  };

  // Skip internal functions
  if (isInternalFunction(func.type)) {
    return [];
  }

  // Check if this function type should be checked
  const shouldCheck =
    (isMutation(func.type) && options.checkMutations) ||
    (isQuery(func.type) && options.checkQueries) ||
    (isAction(func.type) && options.checkActions);

  if (!shouldCheck) {
    return [];
  }

  // Check allowlist patterns
  if (options.allowList.length > 0 && matchesPattern(func.name, options.allowList)) {
    return [];
  }

  // Check for inline suppression
  if (
    options.allowInlineSuppressions &&
    hasSuppression(func.node, 'allow-unauthenticated')
  ) {
    return [];
  }

  // Analyze ctx usage
  const ctxUsage = analyzeCtxUsage(func.node);
  if (ctxUsage.usesAuth) {
    return [];
  }

  // Generate finding with function-type-specific message
  const functionType = isMutation(func.type)
    ? 'Mutation'
    : isQuery(func.type)
      ? 'Query'
      : func.type === 'httpAction'
        ? 'HTTP Action'
        : 'Action';

  return [{
    message: `${functionType} '${func.name}' does not check user authentication`,
    remediation: generateRemediation(func.type),
    // ... standard Finding fields
  }];
}
```
Ensure `isAction` in `src/parser/function-detector.ts` treats `httpAction` as an action so `checkActions` covers it.

Helper function:
```typescript
function generateRemediation(functionType: ConvexFunctionType): string {
  const baseMessage =
    "Add authentication check:\n\n" +
    "const identity = await ctx.auth.getUserIdentity();\n" +
    "if (!identity) throw new Error('Unauthenticated');\n\n";

  const suppressionMessage =
    "If intentionally public:\n" +
    "- Add: // @convex-scanner allow-unauthenticated\n" +
    "- Or configure allowList: ['signup*', 'login']";

  return baseMessage + suppressionMessage;
}
```

### 7. Update Rule Registry and Scanner to Pass Config
```typescript
// src/rules/registry.ts
configure(
  ruleId: string,
  config: { enabled?: boolean; severity?: FindingSeverity; options?: Record<string, unknown> }
): void {
  const existing = this.config.get(ruleId);
  if (existing) {
    this.config.set(ruleId, {
      enabled: config.enabled ?? existing.enabled,
      severity: config.severity ?? existing.severity,
      options: config.options ?? existing.options,
    });
  }
}
// Also update applyConfig to accept `options` and forward to configure.

// src/scanner/static-scanner.ts (around line 154)
registry.applyConfig(config.rules);
if (options.rules) {
  registry.applyConfig(options.rules);
}

for (const { rule, config: ruleConfig } of enabledRules) {
  const contextWithConfig: RuleContext = {
    ...context,
    config: ruleConfig,  // Pass rule config
  };
  const findings = rule.check(contextWithConfig);
  // ...
}
```

### 8. Update Default Configuration
```typescript
// src/config/defaults.ts
export const DEFAULT_CONFIG: Required<ScannerConfig> = {
  convexDir: './convex',
  rules: {
    'auth/missing-auth-check': {
      enabled: true,
      severity: 'high',
      options: {
        checkQueries: true,
        checkMutations: true,
        checkActions: true,
        allowList: [],
        allowInlineSuppressions: true,
      },
    },
  },
  ignore: DEFAULT_IGNORE_PATTERNS,
};
```

### 9. Create Test Fixtures
Create fixture files demonstrating:
- Query without auth (`query-no-auth.ts`)
- Action without auth (`action-no-auth.ts`)
- Action with auth (`action-with-auth.ts`)
- HTTP action without auth (`http-action-no-auth.ts`)
- Mutation with suppression comment (`mutation-with-suppression.ts`)

Example suppression fixture:
```typescript
// @convex-scanner allow-unauthenticated
export const signup = mutation({
  args: { email: v.string() },
  handler: async (ctx, args) => {
    // Intentionally public
  },
});
```

### 10. Add Comprehensive Tests
```typescript
// src/rules/auth/__tests__/missing-auth-check.test.ts

describe('missing-auth-check - enhanced', () => {
  describe('queries', () => {
    it('should flag query without auth check');
    it('should not flag query with auth check');
    it('should not flag query when checkQueries is disabled');
  });

  describe('actions', () => {
    it('should flag action without auth check');
    it('should not flag action with auth check');
    it('should not flag action when checkActions is disabled');
  });

  describe('suppressions', () => {
    it('should respect inline suppression comment');
    it('should respect allowList patterns');
    it('should match function names case-insensitively');
    it('should ignore suppression when allowInlineSuppressions is false');
  });

  describe('internal functions', () => {
    it('should not flag internal query/mutation/action');
  });
  describe('httpAction', () => {
    it('should flag httpAction without auth when checkActions is enabled');
  });
});
```

## Configuration Examples

### Basic Usage (Secure Defaults)
```typescript
// convex-scanner.config.ts
export default {
  rules: {
    'auth/missing-auth-check': {
      enabled: true,  // All defaults apply
    },
  },
};
```

### With Allowlists
```typescript
export default {
  rules: {
    'auth/missing-auth-check': {
      enabled: true,
      severity: 'high',
      options: {
        allowList: [
          'signup*',      // Matches signup, signupWithEmail, etc.
          'login',        // Exact match
          'register*',
          'resetPassword',
          'verifyEmail',
        ],
      },
    },
  },
};
```

### Gradual Rollout (Opt-out Queries/Actions)
```typescript
export default {
  rules: {
    'auth/missing-auth-check': {
      enabled: true,
      options: {
        checkQueries: false,   // Temporarily disable
        checkActions: false,   // Temporarily disable (also disables httpAction)
        checkMutations: true,  // Keep enabled
      },
    },
  },
};
```

## Backward Compatibility

**Breaking Change**: The rule will now check queries, actions, and httpAction by default (previously only mutations).

**Migration Options**:
1. **Accept new defaults** (recommended): Add suppressions where needed
2. **Preserve old behavior**: Set `checkQueries: false, checkActions: false`
3. **Gradual rollout**: Disable, fix findings, then enable

## Testing Strategy

### Unit Tests
- Comment analyzer: All comment parsing edge cases
- Pattern matcher: Glob pattern matching variations
- Enhanced rule: All function type and config combinations
- Registry/config plumbing: `options` propagate from config to rule context

### Integration Tests
- Full scan with new configurations
- Backward compatibility with old configs
- End-to-end suppression workflows

### Regression Tests
- Ensure existing tests still pass
- Verify existing configs still work

## Verification Steps

1. **Run tests**: `npm test` in `packages/convex-scanner`
2. **Test on sample project**:
   ```bash
   cd packages/convex-scanner
   npm run build
   ./dist/cli.js ../../path/to/convex/project
   ```
3. **Verify findings**:
   - Queries without auth are flagged
   - Actions without auth are flagged
   - HTTP actions without auth are flagged
   - Mutations without auth are flagged
   - Suppressed functions are not flagged
   - AllowList patterns work correctly
4. **Test configuration**:
   ```bash
   # Create test config with allowList
   # Run scanner and verify suppressions work
   ```
5. **Test inline suppressions**:
   - Add `// @convex-scanner allow-unauthenticated` to a function
   - Verify it's not flagged
6. **Check markdown output**: Verify remediation messages are clear and helpful

## Success Criteria
- All tests pass (existing + new)
- Queries, actions, and httpAction are checked by default
- Inline suppressions work with `// @convex-scanner allow-unauthenticated`
- AllowList patterns support globs (e.g., `signup*`)
- Remediation messages include suppression instructions
- Configuration is backward compatible (with breaking change note)
- Documentation is updated with examples
