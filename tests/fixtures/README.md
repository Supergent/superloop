# Test Fixtures

Reusable test data for Superloop tests.

## Directory Structure

```
tests/fixtures/
├── configs/                      # Loop configuration files
│   ├── minimal.json              # Minimal valid config with mock runner
│   ├── full-featured.json        # All features enabled
│   └── invalid-*.json            # Invalid configs for testing validation
│
├── session-files/                # Mock AI session files
│   ├── claude-session.jsonl      # Claude API session format
│   └── codex-session.jsonl       # Codex API session format
│
├── state/                        # Loop state snapshots
│   ├── idle/                     # No loop running
│   ├── in-progress/              # Loop actively running
│   ├── awaiting-approval/        # All gates passed except approval
│   ├── stuck/                    # Stuck detection triggered
│   ├── test-failures/            # Tests failing
│   └── complete/                 # Loop completed successfully
│
└── specs/                        # Feature specifications
    └── simple.md                 # Simple feature spec
```

## Usage

### In BATS Tests

```bash
# Copy fixture config to test repo
cp "$BATS_TEST_DIRNAME/../fixtures/configs/minimal.json" "$TEST_REPO/.superloop/config.json"

# Use fixture session file
session_file="$BATS_TEST_DIRNAME/../fixtures/session-files/claude-session.jsonl"
usage=$(extract_claude_usage "$session_file")

# Copy fixture state
cp "$BATS_TEST_DIRNAME/../fixtures/state/complete/state.json" "$TEST_REPO/.superloop/loops/test/state.json"
```

### In TypeScript Tests

```typescript
import fs from 'fs';
import path from 'path';

const fixturesDir = path.join(__dirname, '../../fixtures');
const config = JSON.parse(
  fs.readFileSync(path.join(fixturesDir, 'configs/minimal.json'), 'utf-8')
);
```

## Fixture Descriptions

### Configs

- **minimal.json**: Bare minimum config with mock runner, no gates, 3 max iterations
- **full-featured.json**: All features enabled (tests, evidence, approval, checklists, timeouts, stuck detection)
- **invalid-missing-runners.json**: Missing required `runners` field

### Session Files

- **claude-session.jsonl**: 2 message exchanges with token usage (cumulative: 3500 input, 2000 output, 500 thinking)
- **codex-session.jsonl**: 2 token_count events (cumulative: 3000 input, 1500 output, 600 reasoning, 500 cached)

### State Snapshots

- **idle**: Loop not started (iteration 0)
- **in-progress**: Loop running (iteration 2, implementer phase)
- **awaiting-approval**: All gates passed except approval (iteration 5)
- **complete**: Loop finished successfully (iteration 8, all gates passed)
- **stuck**: Stuck detection triggered after 3 iterations with no changes
- **test-failures**: Tests gate failing (iteration 3, tester phase)

### Specs

- **simple.md**: Basic feature spec with 3 acceptance criteria checkboxes

## Maintenance

When adding new fixtures:
1. Create the fixture file
2. Document it in this README
3. Add test coverage that uses the fixture
