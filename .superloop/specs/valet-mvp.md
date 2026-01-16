# Feature: Valet - AI-Powered Mac Maintenance Assistant

## Overview

Valet is a voice-first macOS menubar application that makes the powerful Mole CLI accessible to non-technical users through an AI assistant interface. Users speak naturally ("Clean my Mac", "Why is it slow?"), and Valet uses Claude to understand intent, execute appropriate Mole commands, and explain results in plain language.

**Key Innovation:** Wraps the open-source Mole tool (tw93/Mole on GitHub) in an ultra-friendly AI layer, making Mac maintenance accessible to everyone while monetizing through a $29/year subscription.

**Market Position:** Competitive with CleanMyMac ($35-90/year) but differentiated by voice-first AI interaction and expandable brand architecture (future: "Valet for Windows", "Valet for Chrome").

## Requirements

### REQ-1: Tauri Desktop Application Foundation
- [ ] Create new Tauri 2.0 project with React + TypeScript frontend
- [ ] Configure for macOS deployment (arm64 + x64 universal binary)
- [ ] Set up menubar-only app (no dock icon, lives in menubar)
- [ ] Implement auto-launch on system startup preference
- [ ] Configure app bundle identifier: `com.valet.mac`

### REQ-2: User Authentication & Subscription Management
- [ ] Integrate Convex backend for user data storage
- [ ] Implement Better-Auth for authentication (email + password)
- [ ] Create subscription tracking (7-day trial, then $29/year)
- [ ] Generate per-user API keys for llm-proxy access
- [ ] Store encrypted API key in secure local storage (macOS Keychain)

### REQ-3: Voice Input via AssemblyAI
- [ ] Port `useAssemblyAIStreaming` hook from Supergent project
- [ ] Implement keyboard shortcut activation (Cmd+Shift+Space)
- [ ] Request microphone permissions during onboarding
- [ ] Stream real-time transcription to UI
- [ ] Handle interim vs final transcripts appropriately

### REQ-4: Voice Output via Vapi
- [ ] Port Vapi TTS integration from Supergent project
- [ ] Implement text-to-speech for Claude responses
- [ ] Add audio playback controls (mute, pause)
- [ ] Configure voice selection (default: professional, neutral)

### REQ-5: Claude Agent SDK Integration
- [ ] Bundle `@anthropic-ai/claude-agent-sdk` in Tauri backend
- [ ] Configure to use llm-proxy.super.gent endpoint
- [ ] Set up workspace at `~/Library/Application Support/Valet/workspace/`
- [ ] Copy bundled `.claude/skills/mole.md` to workspace on first launch
- [ ] Implement tool whitelisting (only allow `Bash` tool)
- [ ] Add PreToolUse hook to validate only `mo` commands are executed
- [ ] Handle conversation state for multi-turn interactions

### REQ-6: Mole CLI Integration
- [ ] Bundle Mole binary in app resources (`YourApp.app/Contents/Resources/mole`)
- [ ] Copy Mole to `~/Library/Application Support/Valet/bin/` on first launch
- [ ] Add to PATH for subprocess execution
- [ ] Implement wrappers for all 7 Mole commands:
  - `mo status` - Real-time system metrics
  - `mo analyze` - Disk space visualization
  - `mo clean` - Cache/log cleanup
  - `mo uninstall <app>` - Complete app removal
  - `mo optimize` - System optimization
  - `mo purge` - Developer artifact cleanup
  - `mo installer` - Installer file cleanup
- [ ] Parse JSON output from `mo status`
- [ ] Parse text output from other commands
- [ ] Handle sudo password prompts for `mo optimize` using Touch ID (native macOS prompt)

### REQ-7: Comprehensive Mole Skills Documentation
- [ ] Create `.claude/skills/mole.md` with complete documentation:
  - All 7 commands with usage patterns
  - Safety rules (always --dry-run first, ask confirmation)
  - Workflow patterns for common scenarios
  - Output parsing instructions
  - When to use each command
- [ ] Include examples of good assistant behavior
- [ ] Document error handling patterns

### REQ-8: Menubar UI - Compact Dropdown
- [ ] Implement menubar icon with color-based health status:
  - Green: System healthy (disk >20GB, CPU/memory normal)
  - Yellow: Warning state (disk 10-20GB or high resource usage)
  - Red: Critical state (disk <10GB or severe performance issues)
  - Animated: AI is actively working
- [ ] Build compact dropdown showing:
  - Health status (Good/Warning/Critical)
  - Live metrics: CPU, RAM, Disk, Network
  - AI insights (e.g., "15 GB recoverable")
  - Voice input field with microphone button
  - Quick action buttons (Clean, Optimize, Deep Scan)
  - Recent activity log
- [ ] Update metrics every 5 seconds via `mo status`
- [ ] Display metrics even when dropdown is closed (in icon tooltip)

### REQ-9: System Monitoring Background Service
- [ ] Run `mo status` every 30 minutes in background
- [ ] Track disk space thresholds (warning: <20GB, critical: <10GB)
- [ ] Update menubar badge when thresholds crossed
- [ ] Store monitoring preferences (check frequency, thresholds)
- [ ] Optional: Show native notification when critical

### REQ-10: Onboarding Flow
- [ ] Screen 1: Welcome + value proposition
- [ ] Screen 2: Account creation (email/password via Better-Auth)
- [ ] Screen 3: Verify Mole installation or guide installation
- [ ] Screen 4: Grant permissions (Full Disk Access, Microphone, Accessibility)
- [ ] Screen 5: Voice activation setup (keyboard shortcut only for MVP)
- [ ] Screen 6: First scan (run `mo status` + `mo analyze`)
- [ ] Screen 7: Results + trial information (7 days free, then $29/year)

### REQ-11: Core Voice Interaction Flows

#### Flow 1: "How's my Mac?"
- [ ] User: Cmd+Shift+Space → "How's my Mac?"
- [ ] AI: Runs `mo status`, parses output
- [ ] AI: Explains metrics in natural language
- [ ] AI: Proactively suggests actions if issues found

#### Flow 2: "Clean my Mac"
- [ ] AI: Runs `mo analyze` to understand disk usage
- [ ] AI: Runs `mo clean --dry-run` to preview
- [ ] AI: Explains what will be cleaned, asks confirmation
- [ ] User: "Yes" (via voice or button)
- [ ] AI: Runs `mo clean`, reports results

#### Flow 3: "Remove Slack"
- [ ] AI: Confirms app name
- [ ] AI: Runs `mo uninstall "Slack"`
- [ ] AI: Explains what's being removed
- [ ] AI: Reports completion and space recovered

#### Flow 4: "Why is my Mac slow?"
- [ ] AI: Runs `mo status` to check metrics
- [ ] AI: Identifies bottleneck (CPU, memory, disk)
- [ ] AI: Explains findings in plain language
- [ ] AI: Suggests appropriate action

### REQ-12: Security & Safety
- [ ] Tool whitelist enforcement (only `Bash` allowed)
- [ ] Command whitelist (only `mo` commands)
- [ ] Log all executed commands for audit
- [ ] Never auto-approve destructive operations (clean, uninstall, optimize)
- [ ] Always show --dry-run preview for cleanup operations
- [ ] Store API keys encrypted in macOS Keychain
- [ ] Rate limiting via llm-proxy (prevent abuse)

### REQ-13: Settings Panel
- [ ] Voice activation toggle (on/off)
- [ ] Monitoring frequency (15min, 30min, hourly, manual)
- [ ] Notification preferences (critical only, suggestions, weekly reports)
- [ ] Alert thresholds (disk space warning/critical levels)
- [ ] Account management (email, subscription status, trial remaining)
- [ ] About section (version, Mole version, privacy policy, terms)

### REQ-14: llm-proxy Integration
- [ ] Reuse existing llm-proxy.super.gent infrastructure
- [ ] Generate user-specific API keys via Convex
- [ ] Track usage per user for billing
- [ ] Implement rate limiting (e.g., 100 requests/day per user)
- [ ] Log all requests for monitoring/debugging
- [ ] Handle API errors gracefully (show user-friendly messages)

### REQ-15: Error Handling & Offline Mode
- [ ] If Claude API is down, show clear error message in UI
- [ ] Allow viewing cached system metrics (last successful `mo status`)
- [ ] Disable voice AI features when offline, but keep metrics display working
- [ ] Show connectivity status in menubar dropdown
- [ ] Retry failed API requests with exponential backoff (max 3 attempts)

### REQ-16: Usage Telemetry & Analytics
- [ ] Track anonymized usage metrics in Convex:
  - Commands executed (e.g., "clean", "status", "uninstall")
  - Space recovered (bytes)
  - Errors encountered (error types, not personal data)
  - Session duration
  - Voice activation frequency
- [ ] No personally identifiable information (PII) collected
- [ ] Include opt-out preference in Settings
- [ ] Use metrics to improve product and detect issues

## Technical Approach

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Valet.app (Tauri)                        │
│                                                             │
│  Frontend (React + TypeScript)                              │
│  ├── Menubar UI (compact dropdown)                          │
│  ├── Settings panel                                         │
│  ├── Onboarding flow                                        │
│  └── Voice interaction components                           │
│                                                             │
│  Backend (Rust + Node.js IPC)                               │
│  ├── Claude Agent SDK (Node.js)                             │
│  ├── AssemblyAI STT integration                             │
│  ├── Vapi TTS integration                                   │
│  ├── Mole CLI executor                                      │
│  └── Background monitoring service                          │
└─────────────────────────────────────────────────────────────┘
                           ↓
                  llm-proxy.super.gent
                           ↓
                  Anthropic API (Claude Max)
                           ↓
                  Convex (auth + usage tracking)
```

### Key Files & Patterns

**Project Structure:**
```
valet/
├── src-tauri/               # Tauri backend (Rust)
│   ├── src/
│   │   ├── main.rs          # Menubar app setup
│   │   ├── monitoring.rs    # Background monitoring
│   │   └── permissions.rs   # macOS permission handling
│   └── tauri.conf.json      # Tauri configuration
│
├── src/                     # React frontend
│   ├── components/
│   │   ├── MenubarDropdown.tsx    # Main UI
│   │   ├── VoiceInput.tsx         # Voice activation
│   │   ├── MetricsDisplay.tsx     # Live stats
│   │   └── Onboarding/            # Onboarding screens
│   ├── hooks/
│   │   ├── useAssemblyAI.ts       # Port from Supergent
│   │   ├── useVapi.ts             # Port from Supergent
│   │   └── useClaudeAgent.ts      # Agent SDK wrapper
│   └── lib/
│       ├── agent.ts               # Claude Agent SDK integration
│       ├── mole.ts                # Mole CLI wrappers
│       └── convex.ts              # Convex client
│
├── convex/                  # Convex backend
│   ├── schema.ts            # User, subscription, apiKeys tables
│   ├── auth.ts              # Better-Auth integration
│   └── endpoints/
│       └── apiKeys.ts       # API key management
│
└── resources/               # Bundled assets
    └── .claude/
        └── skills/
            └── mole.md      # Comprehensive Mole documentation
```

**Agent SDK Integration Pattern (from Supergent):**
```typescript
import { query } from '@anthropic-ai/claude-agent-sdk';

async function askClaude(userMessage: string, sessionId?: string) {
  const workspace = await getWorkspace(); // ~/Library/Application Support/Valet/workspace/

  const response = query({
    prompt: userMessage,
    options: {
      cwd: workspace,
      model: 'claude-sonnet-4-20250514',
      settingSources: ['project'],  // Auto-loads .claude/skills/mole.md
      systemPrompt: "You are Valet, a Mac maintenance assistant.",
      resume: sessionId,  // Multi-turn conversation

      allowedTools: ['Bash'],  // ONLY Bash tool

      hooks: {
        PreToolUse: [{
          hooks: [async (input) => {
            // SECURITY: Whitelist only `mo` commands
            if (input.tool_name === 'Bash') {
              const cmd = input.tool_input?.command || '';
              if (!cmd.trim().startsWith('mo ')) {
                throw new Error('Only Mole commands are allowed');
              }
            }
            return {};
          }]
        }],
        PostToolUse: [{
          hooks: [async (input) => {
            // Log command execution for audit
            await logCommand(input);
            return {};
          }]
        }]
      }
    }
  });

  // Stream processing...
  for await (const message of response) {
    if (message.type === 'text') {
      // Send to TTS
    }
  }
}
```

**Voice Integration (from Supergent patterns):**
- AssemblyAI: `apps/supergent/src/hooks/useAssemblyAIStreaming.ts`
- Vapi: `apps/supergent/src/providers/vapi-provider.tsx`
- Event bus: `apps/supergent/src/lib/voice/events/`

**Convex Integration:**
- Better-Auth setup: Follow `apps/supergent/convex/auth.ts`
- API key management: Follow `apps/supergent/convex/endpoints/apiKeys.ts`
- Schema: Users, subscriptions, apiKeys, usageLogs tables

**Mole CLI Wrapper Example:**
```typescript
import { Command } from '@tauri-apps/api/shell';

export async function executeStatusCheck(): Promise<SystemMetrics> {
  const command = new Command('mo', ['status', '--json']);
  const output = await command.execute();

  if (output.code !== 0) {
    throw new Error(`mo status failed: ${output.stderr}`);
  }

  return JSON.parse(output.stdout);
}

export async function executeClean(dryRun: boolean = true): Promise<CleanResult> {
  const args = dryRun ? ['clean', '--dry-run'] : ['clean'];
  const command = new Command('mo', args);
  const output = await command.execute();

  return parseCleanOutput(output.stdout);
}
```

### Dependencies

**Frontend:**
- `@tauri-apps/api` - Tauri API bindings
- `react` + `react-dom` - UI framework
- `convex` - Backend client
- `@better-auth/react` - Authentication

**Backend (Tauri):**
- `@anthropic-ai/claude-agent-sdk` - AI agent
- Node.js runtime for SDK execution
- AssemblyAI WebSocket client
- Vapi SDK for TTS

**Convex:**
- `better-auth` - Authentication
- `convex` - Backend framework

### Configuration

**Environment Variables:**
```env
# Convex
CONVEX_DEPLOYMENT=https://your-deployment.convex.cloud
CONVEX_DEPLOY_KEY=...

# llm-proxy
LLM_PROXY_URL=https://llm-proxy.super.gent

# AssemblyAI
ASSEMBLYAI_API_KEY=...

# Vapi
VAPI_PUBLIC_KEY=...
```

**Tauri Configuration:**
```json
{
  "tauri": {
    "bundle": {
      "active": true,
      "targets": ["app", "dmg"],
      "identifier": "com.valet.mac",
      "icon": ["icons/icon.icns"],
      "resources": ["resources/.claude/**"]
    },
    "systemTray": {
      "iconPath": "icons/tray-icon.png",
      "menuOnLeftClick": false
    },
    "security": {
      "dangerousDisableAssetCspModification": true
    },
    "allowlist": {
      "fs": {
        "all": true,
        "scope": ["$APPDATA/*"]
      },
      "shell": {
        "all": true,
        "execute": true,
        "sidecar": false,
        "scope": [
          {
            "name": "mo",
            "cmd": "mo",
            "args": true
          }
        ]
      }
    }
  }
}
```

## Acceptance Criteria

### AC-1: Voice Interaction Works End-to-End
- [ ] When user presses Cmd+Shift+Space and says "How's my Mac?"
- [ ] Then AssemblyAI captures speech, Claude Agent analyzes via `mo status`
- [ ] And Vapi speaks response explaining system health in plain language

### AC-2: Storage Cleanup Flow Is Safe
- [ ] When user says "Clean my Mac"
- [ ] Then AI runs `mo clean --dry-run` first
- [ ] And shows user preview of what will be deleted
- [ ] And asks explicit confirmation before running actual `mo clean`
- [ ] And reports bytes recovered after completion

### AC-3: App Uninstall Is Complete
- [ ] When user says "Remove Slack"
- [ ] Then AI runs `mo uninstall "Slack"`
- [ ] And removes app bundle, caches, preferences, login items
- [ ] And reports total space recovered

### AC-4: System Monitoring Is Proactive
- [ ] When disk space drops below 10GB
- [ ] Then menubar icon shows critical badge
- [ ] And optional notification appears
- [ ] And AI proactively suggests cleanup when user opens dropdown

### AC-5: Security Constraints Are Enforced
- [ ] When Claude attempts to run any non-`mo` command
- [ ] Then PreToolUse hook rejects the command
- [ ] And user sees error message
- [ ] And command is logged for audit

### AC-6: Subscription Trial Works
- [ ] When new user completes onboarding
- [ ] Then 7-day trial starts automatically
- [ ] And trial expiration date shows in settings
- [ ] And after 7 days, app prompts for payment
- [ ] And usage is tracked via llm-proxy API key

### AC-7: Multi-Turn Conversations Work
- [ ] When user asks "How's my Mac?" then "Clean the caches"
- [ ] Then Claude maintains conversation context using session ID
- [ ] And understands "the caches" refers to previous analysis
- [ ] And executes appropriate cleanup command

### AC-8: Onboarding Catches Missing Dependencies
- [ ] When user launches app for first time without Mole installed
- [ ] Then onboarding detects missing `mo` command
- [ ] And provides instructions to install via Homebrew
- [ ] And verifies installation before proceeding

## Constraints

- **macOS Only**: MVP targets macOS 12.0+ (Monterey and later)
- **Mole Required**: Requires Mole CLI to be installed (guide user to install via Homebrew)
- **Internet Required**: Needs internet for Claude API calls via llm-proxy
- **Microphone Required**: Voice features require microphone permission
- **Full Disk Access Required**: Mole needs Full Disk Access to scan/clean system files
- **Performance**: Background monitoring should use <1% CPU when idle
- **Latency**: Voice response should begin within 2 seconds of user finishing speaking
- **API Costs**: Average user should cost <$2/month in Claude API usage (covered by $29/year subscription)

## Out of Scope (MVP)

The following features are explicitly deferred to post-MVP:

- **Wake word activation** - "Hey Valet" always-listening mode (battery/privacy concerns)
- **Multi-language support** - English only for MVP
- **Windows/Linux versions** - macOS only initially
- **Advanced scheduling** - "Clean my Mac every Sunday at 3am"
- **Detailed analytics dashboard** - Web dashboard showing historical metrics
- **Team/family plans** - Multi-device subscriptions
- **Integration with other tools** - No TimeMachine, no cloud backup integration
- **Custom cleanup rules** - User-defined file patterns to clean
- **Browser extension** - "Valet for Chrome" is future product
- **Mobile companion app** - iOS/Android remote control

## Test Commands

### Unit Tests
```bash
# Frontend tests
cd valet
npm test

# Tauri backend tests
cd src-tauri
cargo test
```

### Integration Tests
```bash
# Test Mole CLI integration
npm run test:mole

# Test Claude Agent integration
npm run test:agent

# Test voice pipeline
npm run test:voice
```

### Manual Testing Checklist
- [ ] Install app on clean Mac
- [ ] Complete onboarding flow
- [ ] Grant all required permissions
- [ ] Test voice activation (Cmd+Shift+Space)
- [ ] Say "How's my Mac?" and verify response
- [ ] Say "Clean my Mac" and verify --dry-run preview
- [ ] Approve cleanup and verify execution
- [ ] Check menubar metrics update every 5 seconds
- [ ] Verify background monitoring (artificially trigger low disk space)
- [ ] Test subscription trial countdown in settings
- [ ] Verify API key is stored encrypted in Keychain
- [ ] Test multi-turn conversation (ask follow-up questions)
- [ ] Verify command whitelisting (attempt to trigger non-mo command)

### Convex Deployment
```bash
# Deploy Convex backend
cd convex
npx convex deploy --prod

# Verify endpoints
npx convex dev
```

### Tauri Build
```bash
# Development build
npm run tauri dev

# Production build (universal binary)
npm run tauri build -- --target universal-apple-darwin

# Verify bundle
ls -lh src-tauri/target/release/bundle/macos/Valet.app
```

## Implementation Notes

### Bundling Mole
- Mole binary will be bundled in app resources and copied to user's Library on first launch
- App controls Mole version (no external dependency on Homebrew)
- Updates to Mole distributed via app updates

### Sudo Handling
- Use native macOS Touch ID prompts for `mo optimize` (no privileged helper needed)
- Touch ID requested each time sudo is required
- Clear explanation shown to user before prompting

### Visual Design
- Menubar icon color indicates system health (green/yellow/red)
- Smooth color transitions to avoid jarring changes
- Icon remains recognizable across all states

### Graceful Degradation
- If Claude API unavailable, app shows cached metrics but disables AI features
- Clear error messaging explains what's not working
- App remains useful for viewing system status even offline
