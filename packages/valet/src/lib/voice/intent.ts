/**
 * Voice Intent Detection
 * Helpers to detect user intentions from voice transcripts
 */

import { VoiceIntent } from './types';

// ============================================================================
// Confirmation Detection
// ============================================================================

/**
 * Patterns for affirmative responses
 */
const AFFIRMATIVE_PATTERNS = [
  /^yes$/i,
  /^yeah$/i,
  /^yep$/i,
  /^sure$/i,
  /^okay$/i,
  /^ok$/i,
  /^alright$/i,
  /^go ahead$/i,
  /^do it$/i,
  /^proceed$/i,
  /^confirm$/i,
  /^affirmative$/i,
];

/**
 * Patterns for negative responses
 */
const NEGATIVE_PATTERNS = [
  /^no$/i,
  /^nope$/i,
  /^nah$/i,
  /^cancel$/i,
  /^stop$/i,
  /^abort$/i,
  /^don'?t$/i,
  /^negative$/i,
  /^never ?mind$/i,
];

/**
 * Detect if a transcript is an affirmative confirmation
 * @param transcript - The voice transcript text
 * @returns true if affirmative, false otherwise
 */
export function isAffirmative(transcript: string): boolean {
  const normalized = transcript.trim().toLowerCase();
  return AFFIRMATIVE_PATTERNS.some(pattern => pattern.test(normalized));
}

/**
 * Detect if a transcript is a negative/rejection response
 * @param transcript - The voice transcript text
 * @returns true if negative, false otherwise
 */
export function isNegative(transcript: string): boolean {
  const normalized = transcript.trim().toLowerCase();
  return NEGATIVE_PATTERNS.some(pattern => pattern.test(normalized));
}

/**
 * Detect if a transcript is a confirmation (yes or no)
 * @param transcript - The voice transcript text
 * @returns 'yes', 'no', or null if not a confirmation
 */
export function detectConfirmation(transcript: string): 'yes' | 'no' | null {
  if (isAffirmative(transcript)) return 'yes';
  if (isNegative(transcript)) return 'no';
  return null;
}

// ============================================================================
// App Name Extraction
// ============================================================================

/**
 * Generic placeholders that should not be treated as real app names
 */
const GENERIC_PLACEHOLDERS = [
  'something',
  'it',
  'this',
  'that',
  'app',
  'application',
  'program',
  'software',
  'thing',
  'one',
];

/**
 * Extract application name from uninstall requests
 * Handles patterns like:
 * - "Remove Slack"
 * - "Uninstall Chrome"
 * - "Delete Microsoft Word"
 * - "Get rid of Adobe Photoshop"
 */
export function extractUninstallTarget(transcript: string): string | null {
  const patterns = [
    // "Remove <app>"
    /(?:remove|delete|uninstall|get rid of)\s+(?:the\s+)?(.+?)(?:\s+app(?:lication)?)?$/i,
    // "<app> removal"
    /(.+?)\s+(?:removal|uninstall|deletion)$/i,
  ];

  for (const pattern of patterns) {
    const match = transcript.trim().match(pattern);
    if (match && match[1]) {
      // Clean up the extracted app name
      let appName = match[1].trim()
        // Remove articles
        .replace(/^(?:a|an|the)\s+/i, '')
        // Strip trailing punctuation
        .replace(/[.,;!?]+$/, '')
        // Remove filler words like "some" or "any"
        .replace(/^(?:some|any)\s+/i, '');

      // Normalize and check if the name is a generic placeholder
      const normalized = appName.trim().toLowerCase();
      if (GENERIC_PLACEHOLDERS.includes(normalized)) {
        return null;
      }

      // Capitalize first letter of each word
      appName = appName
        .split(' ')
        .map(word => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
        .join(' ');

      return appName;
    }
  }

  return null;
}

// ============================================================================
// Intent Classification
// ============================================================================

/**
 * Intent patterns for common Mac maintenance tasks
 */
const INTENT_PATTERNS = {
  status: [
    /how'?s my mac/i,
    /what'?s (?:the )?status/i,
    /system status/i,
    /health check/i,
    /check (?:my )?mac/i,
  ],
  clean: [
    /clean (?:my )?mac/i,
    /free (?:up )?space/i,
    /clear (?:out )?junk/i,
    /remove (?:temporary|temp) files/i,
    /clean(?:up)?/i,
  ],
  optimize: [
    /optimize (?:my )?mac/i,
    /speed (?:up|it up)/i,
    /make (?:it|my mac) faster/i,
    /improve performance/i,
  ],
  uninstall: [
    /(?:remove|delete|uninstall|get rid of)\s+.+/i,
    /.+\s+(?:removal|uninstall)/i,
  ],
  analyze: [
    /deep scan/i,
    /analyze (?:disk|storage)/i,
    /what'?s using (?:my )?space/i,
    /disk usage/i,
  ],
  help: [
    /help/i,
    /what can you do/i,
    /how do (?:I|you)/i,
    /tell me (?:about|more)/i,
  ],
} as const;

/**
 * Classify a voice transcript into an intent
 * @param transcript - The voice transcript text
 * @returns VoiceIntent object with detected intent and entities
 */
export function classifyIntent(transcript: string): VoiceIntent {
  const normalized = transcript.trim().toLowerCase();

  // Check for status intent
  for (const pattern of INTENT_PATTERNS.status) {
    if (pattern.test(normalized)) {
      return {
        transcript,
        intent: 'status',
        confidence: 0.9,
      };
    }
  }

  // Check for clean intent
  for (const pattern of INTENT_PATTERNS.clean) {
    if (pattern.test(normalized)) {
      return {
        transcript,
        intent: 'clean',
        confidence: 0.9,
      };
    }
  }

  // Check for optimize intent
  for (const pattern of INTENT_PATTERNS.optimize) {
    if (pattern.test(normalized)) {
      return {
        transcript,
        intent: 'optimize',
        confidence: 0.9,
      };
    }
  }

  // Check for uninstall intent and extract app name
  for (const pattern of INTENT_PATTERNS.uninstall) {
    if (pattern.test(normalized)) {
      const appName = extractUninstallTarget(transcript);
      return {
        transcript,
        intent: 'uninstall',
        entities: appName ? { appName } : undefined,
        // Lower confidence when app name is missing/ambiguous
        confidence: appName ? 0.9 : 0.3,
      };
    }
  }

  // Check for analyze intent
  for (const pattern of INTENT_PATTERNS.analyze) {
    if (pattern.test(normalized)) {
      return {
        transcript,
        intent: 'analyze',
        confidence: 0.9,
      };
    }
  }

  // Check for help intent
  for (const pattern of INTENT_PATTERNS.help) {
    if (pattern.test(normalized)) {
      return {
        transcript,
        intent: 'help',
        confidence: 0.8,
      };
    }
  }

  // Unknown intent
  return {
    transcript,
    intent: 'unknown',
    confidence: 0,
  };
}

/**
 * Check if an intent requires agent processing
 * Simple intents like status/help can be handled directly,
 * while complex intents like clean/optimize require the agent
 */
export function requiresAgent(intent: VoiceIntent): boolean {
  // All intents benefit from agent processing for natural responses
  return true;
}

// ============================================================================
// Intent to Prompt Conversion
// ============================================================================

/**
 * Convert a detected intent into an enhanced agent prompt
 * Adds context and guidance to improve agent responses
 */
export function intentToPrompt(intent: VoiceIntent): string {
  const { transcript, intent: intentType, entities } = intent;

  switch (intentType) {
    case 'status':
      return `${transcript}\n\nPlease run 'mo status' and explain the Mac's health status in a friendly, conversational way.`;

    case 'clean':
      return `${transcript}\n\nPlease help me clean my Mac. First run 'mo clean --dry-run' to preview what will be cleaned, then explain what you found and ask for confirmation before running the actual cleanup.`;

    case 'optimize':
      return `${transcript}\n\nPlease help me optimize my Mac. First run 'mo optimize --dry-run' to preview the optimizations, then explain what will be done and ask for confirmation.`;

    case 'uninstall':
      if (entities?.appName) {
        return `${transcript}\n\nPlease help me uninstall "${entities.appName}". Use 'mo uninstall "${entities.appName}"' and explain how much space will be recovered. Make sure to confirm with me before actually uninstalling.`;
      }
      return `${transcript}\n\nPlease help me uninstall an application. Can you clarify which app I want to remove?`;

    case 'analyze':
      return `${transcript}\n\nPlease analyze my disk usage with 'mo analyze' and explain what's taking up the most space in a clear, conversational way.`;

    case 'help':
      return `${transcript}\n\nPlease explain what you can help me with. Mention that you can check Mac health, clean up space, optimize performance, uninstall apps, and analyze disk usage.`;

    case 'unknown':
    default:
      // Let the agent handle unknown intents naturally
      return transcript;
  }
}

// ============================================================================
// Exports
// ============================================================================

export default {
  isAffirmative,
  isNegative,
  detectConfirmation,
  extractUninstallTarget,
  classifyIntent,
  requiresAgent,
  intentToPrompt,
};
