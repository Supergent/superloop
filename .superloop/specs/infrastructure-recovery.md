# Infrastructure Recovery System

## Problem Statement

Superloop agents can diagnose infrastructure issues but cannot act on them. This creates a failure mode where:

1. Tests fail due to infrastructure problems (dependency conflicts, config issues)
2. Tester correctly diagnoses the problem and proposes a fix
3. Implementer sees the diagnosis but is not permitted to execute recovery commands
4. Loop iterates repeatedly, burning resources, until human intervenes or stuck threshold is reached

**Real example from pinpoint-v1 loop (2026-01-23):**

```
Issue: esbuild version mismatch (0.21.5 vs 0.27.2)
Tester diagnosis: "Fix Required: rm -rf node_modules && bun install"
Implementer response: "Blocked on instruction not to modify node_modules"
Result: 6+ iterations wasted before human intervention
```

## Goals

1. Enable automatic recovery from common infrastructure failures
2. Maintain safety - only execute pre-approved recovery commands
3. Preserve human oversight for unknown/risky recovery actions
4. Zero maintenance burden - agents diagnose, config defines safety boundaries

## Non-Goals

- Giving agents unrestricted shell access
- Automatic recovery from code/logic bugs (that's the normal loop)
- Replacing human judgment for novel failure modes

## Design Principles

1. **Agents diagnose, wrapper executes** - Leverage AI's diagnostic ability, but keep execution at wrapper level
2. **Whitelist, not blacklist** - Only explicitly approved commands can auto-execute
3. **Structured proposals** - Agents output machine-parseable recovery requests
4. **Graceful escalation** - Unknown issues pause loop and notify humans

---

## Architecture

### Current Flow (No Recovery)

```
Iteration N:
  Planner → Implementer → Tester → Reviewer
  │                        │
  │                        ├─ Tests fail (infra issue)
  │                        └─ Writes diagnosis to test-report.md
  │
  └─ Reviewer sees failure, doesn't emit promise

Iteration N+1:
  (Same failure repeats)
```

### Proposed Flow (With Recovery)

```
Iteration N:
  Planner → Implementer → Tester → Reviewer
  │                        │
  │                        ├─ Tests fail (infra issue)
  │                        ├─ Writes diagnosis to test-report.md
  │                        └─ Writes recovery.json (NEW)
  │
  └─ Reviewer sees failure, doesn't emit promise

Post-Iteration Check (NEW):
  Wrapper reads recovery.json
  │
  ├─ Command in auto_approve list?
  │   └─ YES → Execute recovery, log result, continue to next iteration
  │
  ├─ Command in require_human list?
  │   └─ YES → Pause loop, emit escalation, wait for human
  │
  └─ Unknown command?
      └─ Pause loop, emit escalation, wait for human

Iteration N+1:
  (Infra issue resolved, tests pass)
```

---

## Specification

### 1. Recovery Proposal Format

The Tester outputs `recovery.json` when it detects infrastructure issues:

```json
{
  "version": 1,
  "timestamp": "2026-01-23T05:36:33Z",
  "category": "dependency",
  "severity": "blocking",
  "diagnosis": {
    "error_pattern": "Cannot start service: Host version .* does not match binary version",
    "root_cause": "esbuild version mismatch between vite and vitest dependencies",
    "evidence": [
      "test-output.txt:3: Host version \"0.21.5\" does not match binary version \"0.27.2\""
    ]
  },
  "recovery": {
    "command": "rm -rf node_modules && bun install",
    "working_dir": ".",
    "timeout_seconds": 300,
    "expected_outcome": "Consistent esbuild versions, vitest can start",
    "confidence": "high"
  },
  "fallback": {
    "command": "bun install --force",
    "confidence": "medium"
  }
}
```

**Fields:**

| Field | Required | Description |
|-------|----------|-------------|
| `version` | Yes | Schema version for forward compatibility |
| `timestamp` | Yes | When diagnosis was made |
| `category` | Yes | One of: `dependency`, `config`, `environment`, `permissions`, `network` |
| `severity` | Yes | `blocking` (tests can't run) or `degraded` (partial failure) |
| `diagnosis.error_pattern` | Yes | Regex that matched the failure |
| `diagnosis.root_cause` | Yes | Human-readable explanation |
| `diagnosis.evidence` | Yes | File:line references supporting diagnosis |
| `recovery.command` | Yes | Shell command to execute |
| `recovery.working_dir` | No | Directory to run command in (default: repo root) |
| `recovery.timeout_seconds` | No | Max execution time (default: 120) |
| `recovery.expected_outcome` | Yes | What success looks like |
| `recovery.confidence` | Yes | `high`, `medium`, `low` |
| `fallback` | No | Alternative recovery if primary fails |

### 2. Config Schema Extension

Add to `config.json`:

```json
{
  "recovery": {
    "enabled": true,
    "auto_approve": [
      "bun install",
      "npm install",
      "yarn install",
      "pnpm install",
      "rm -rf node_modules && bun install",
      "rm -rf node_modules && npm install",
      "rm -rf .next && bun run build",
      "rm -rf dist && bun run build"
    ],
    "require_human": [
      "rm -rf *",
      "git reset --hard",
      "git push",
      "curl *",
      "wget *"
    ],
    "max_auto_recoveries_per_run": 3,
    "cooldown_seconds": 60,
    "on_unknown": "escalate"
  }
}
```

**Fields:**

| Field | Default | Description |
|-------|---------|-------------|
| `enabled` | `true` | Master switch for recovery system |
| `auto_approve` | `[]` | Commands that can execute without human approval |
| `require_human` | `["*"]` | Patterns that always require human approval |
| `max_auto_recoveries_per_run` | `3` | Prevent infinite recovery loops |
| `cooldown_seconds` | `60` | Minimum time between auto-recoveries |
| `on_unknown` | `"escalate"` | What to do with unrecognized commands: `escalate`, `deny`, `allow` |

### 3. Escalation Mechanism

When human intervention is required, the wrapper:

1. Writes `escalation.json`:

```json
{
  "timestamp": "2026-01-23T05:40:00Z",
  "loop_id": "pinpoint-v1",
  "iteration": 6,
  "type": "recovery_approval_required",
  "status": "pending",
  "recovery_proposal": { /* from recovery.json */ },
  "reason": "Command not in auto_approve list",
  "actions": {
    "approve": "superloop.sh approve-recovery --loop pinpoint-v1",
    "reject": "superloop.sh reject-recovery --loop pinpoint-v1",
    "manual": "cd /path/to/repo && rm -rf node_modules && bun install"
  }
}
```

2. Pauses the loop (sets `state.json` status to `"awaiting_human"`)

3. Optionally sends notification (webhook, if configured):

```json
{
  "webhooks": {
    "on_escalation": "https://hooks.slack.com/..."
  }
}
```

4. Waits for human action via:
   - `superloop.sh approve-recovery --loop <id>` - Execute proposed command
   - `superloop.sh reject-recovery --loop <id>` - Skip recovery, continue loop
   - `superloop.sh resolve-recovery --loop <id> --note "Fixed manually"` - Mark resolved

### 4. Tester Role Update

Add to `roles/tester.md`:

```markdown
## Infrastructure Analysis

When tests fail to execute (not test logic failures), analyze for infrastructure issues:

1. **Identify category**: dependency, config, environment, permissions, network
2. **Extract evidence**: specific error messages with file:line references
3. **Propose recovery**: specific command that would fix the issue
4. **Assess confidence**: high (seen this exact pattern), medium (similar patterns), low (best guess)

**Output `recovery.json`** when you identify a recoverable infrastructure issue.

Do NOT propose recovery for:
- Test logic failures (assertions failing)
- Code bugs (the normal iteration loop handles these)
- Issues requiring code changes (Implementer's job)

DO propose recovery for:
- Dependency version conflicts
- Missing dependencies
- Corrupted node_modules
- Build cache issues
- Config file syntax errors (if auto-fixable)
```

### 5. Event Log Entries

New events for `events.jsonl`:

```json
{"event": "recovery_proposed", "category": "dependency", "command": "bun install", "confidence": "high"}
{"event": "recovery_approved", "source": "auto", "command": "bun install"}
{"event": "recovery_executed", "command": "bun install", "exit_code": 0, "duration_ms": 4523}
{"event": "recovery_failed", "command": "bun install", "exit_code": 1, "error": "..."}
{"event": "recovery_escalated", "reason": "command not in auto_approve", "awaiting": "human"}
{"event": "recovery_resolved", "by": "human", "method": "manual", "note": "Ran command manually"}
```

---

## Implementation Phases

### Phase 1: Core Recovery Loop (MVP)

1. [ ] Add `recovery` section to config schema
2. [ ] Update Tester role prompt to output `recovery.json`
3. [ ] Add post-iteration recovery check to wrapper
4. [ ] Implement auto-approve command matching
5. [ ] Execute approved recoveries and log results
6. [ ] Add recovery events to events.jsonl

**Acceptance Criteria:**
- AC-1: When Tester outputs recovery.json with command in auto_approve, wrapper executes it
- AC-2: When recovery succeeds, next iteration runs normally
- AC-3: When recovery fails, escalation is triggered
- AC-4: Recovery attempts are logged in events.jsonl
- AC-5: Max auto-recoveries limit is enforced

### Phase 2: Escalation System

1. [ ] Implement escalation.json generation
2. [ ] Add `awaiting_human` state to state.json
3. [ ] Implement `approve-recovery` / `reject-recovery` / `resolve-recovery` commands
4. [ ] Add webhook notification support
5. [ ] Update dashboard to show escalation UI

**Acceptance Criteria:**
- AC-6: Unknown commands trigger escalation
- AC-7: Loop pauses until human responds
- AC-8: All three resolution methods work (approve, reject, resolve)
- AC-9: Webhook fires on escalation (when configured)

### Phase 3: Config Hot-Reload

1. [ ] Re-read config.json at start of each iteration
2. [ ] Validate config changes don't break running loop
3. [ ] Log config changes in events.jsonl

**Acceptance Criteria:**
- AC-10: Changes to auto_approve list take effect next iteration
- AC-11: Invalid config changes are rejected with clear error
- AC-12: Config reload is logged

---

## Security Considerations

1. **Command injection**: Auto-approve list uses exact string matching, not shell expansion
2. **Path traversal**: `working_dir` must be within repo root
3. **Resource exhaustion**: Timeout and max-recoveries limits prevent runaway processes
4. **Credential exposure**: Recovery commands should not include secrets (use env vars)

## Backwards Compatibility

- `recovery` config section is optional; if absent, behavior unchanged
- Existing loops continue to work without modification
- Tester only outputs recovery.json if prompted to (role update)

## Metrics

Track in usage.jsonl:
- Recovery proposals per loop
- Auto-recovery success rate
- Escalation frequency
- Time-to-resolution for escalations
- Most common recovery categories

---

## Appendix: Common Recovery Patterns

### Dependency Issues

| Pattern | Recovery |
|---------|----------|
| `Cannot find module` | `bun install` |
| `version mismatch` | `rm -rf node_modules && bun install` |
| `ERESOLVE` | `npm install --legacy-peer-deps` |
| `lockfile out of sync` | `bun install` |

### Build Issues

| Pattern | Recovery |
|---------|----------|
| `ENOENT.*dist` | `bun run build` |
| `Cannot find.*\.next` | `rm -rf .next && bun run build` |
| `tsc.*error TS` | (Not auto-recoverable - code issue) |

### Environment Issues

| Pattern | Recovery |
|---------|----------|
| `EACCES` | (Escalate - permissions issue) |
| `ENOSPC` | (Escalate - disk space) |
| `ENOMEM` | (Escalate - memory) |

---

*Spec version: 1.0*
*Author: Claude + Human*
*Date: 2026-01-23*
