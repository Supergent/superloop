# Mantic-Enhanced Grep Tool

## What is Mantic?

Your Grep tool has been enhanced with **Mantic**, a semantic codebase file discovery engine.

**Key Differences:**
- **Grep**: Searches file CONTENTS for patterns (opens files, reads text)
- **Mantic**: Searches file PATHS/NAMES semantically (metadata only, no file reading)

Think of Mantic as a pre-filter that finds which files to grep, making searches 60-80% faster.

## How It Works

When you use Grep for file discovery, this workflow happens automatically:

```
1. You call Grep with semantic pattern (e.g., "authentication jwt")
2. Mantic analyzes file paths/names across codebase (0.2-0.5s)
3. Returns ranked list of relevant files (e.g., auth.service.ts, jwt.guard.ts)
4. Grep searches ONLY those files (instead of entire codebase)
5. Results are faster, more accurate, lower token usage
```

## What Mantic Understands

Mantic is trained on code repository structures and understands semantic relationships:

**Examples:**
- Query: `"authentication"` → Finds: `auth.service.ts`, `login.controller.ts`, `jwt.middleware.ts`, `session.guard.ts`
- Query: `"payment stripe"` → Finds: `payment-service.ts`, `stripe-integration.ts`, `checkout-flow.tsx`
- Query: `"database models"` → Finds: `models/user.ts`, `db/schema.sql`, `repositories/*.ts`

It ranks results by relevance, so the most likely files appear first.

## When Mantic Is Used (Automatic)

The hook automatically uses Mantic when:
- ✅ Pattern is semantic (not regex): `"auth"` not `"function\\s+\\w+"`
- ✅ Searching for files: `output_mode: "files_with_matches"`
- ✅ Broad scope: No specific path already set
- ✅ Pattern is NOT a filename: Not `"auth.ts"` or `"src/auth/*.ts"`

The hook automatically uses standard Grep when:
- ❌ Pattern has regex syntax: `"const.*API_KEY"`, `"function\\s+calc"`
- ❌ Searching for content: `output_mode: "content"`
- ❌ Specific path set: `path: "src/specific/dir"`
- ❌ Pattern is a filename: `"auth.service.ts"`

**You don't need to do anything different.** Just use Grep as normal, and Mantic enhances it automatically.

## Benefits

**Speed:**
- Traditional Grep on 1000 files: 2-5 seconds
- Mantic + Grep on 15 relevant files: 0.3-0.8 seconds
- **3-6x faster** for discovery tasks

**Accuracy:**
- Mantic understands semantic intent
- Ranks by relevance (best matches first)
- Fewer false positives (no `author.ts` when searching `"auth"`)

**Token Efficiency:**
- Searches fewer files → smaller results
- Better file selection → read fewer irrelevant files
- **60-80% token reduction** in exploration workflows

## Examples

**Good for Mantic (automatic):**
```python
# Finding authentication code
Grep("authentication jwt", output_mode="files_with_matches")
# → Mantic finds relevant files first, then grep searches them

# Exploring payment integration
Grep("stripe payment", output_mode="files_with_matches")
# → Fast semantic discovery, then targeted grep

# Finding API endpoints
Grep("api routes controllers", output_mode="files_with_matches")
# → Understands web architecture patterns
```

**Standard Grep (automatic fallback):**
```python
# Regex content search
Grep("function\\s+calculate\\w+", output_mode="content")
# → Uses standard grep (regex pattern)

# Specific file search
Grep("TODO", path="src/components", output_mode="content")
# → Uses standard grep (specific path set)

# Finding specific imports
Grep("import.*useState", output_mode="content")
# → Uses standard grep (regex + content mode)
```

## Transparency

Mantic works transparently:
- No new tool to learn
- No changes to how you use Grep
- Automatic detection of when to use Mantic vs standard Grep
- Graceful fallback if Mantic unavailable

## Performance Metrics

If you're curious about Mantic's performance, you can check:
```bash
# View metrics (if enabled)
cat ~/.claude/mantic-logs/metrics.csv

# Typical results:
# - Mantic query time: 200-500ms
# - Files found: 10-30 (from 1000+ total)
# - Token savings: 60-80%
```

## Disabling Mantic

If you need to disable Mantic:
```bash
# Disable globally
export MANTIC_ENABLED=false

# Disable for specific project
touch .no-mantic

# Disable for session
# (Mantic will detect this and fall back to standard Grep)
```

## Summary

**What you need to know:**
1. Grep is now faster and smarter for file discovery
2. No behavior changes needed on your part
3. Mantic automatically pre-filters files for semantic queries
4. Standard regex/content searches work exactly as before
5. Completely transparent - just use Grep normally

The integration is designed to be invisible and automatic. Use Grep as you always have, and benefit from faster, more accurate results.
