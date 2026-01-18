/**
 * Rule registry - manages and configures rules
 */

import type { Rule, RuleConfiguration } from './rule.js';
import type { FindingSeverity } from '../types.js';
import { missingAuthCheckRule } from './auth/missing-auth-check.js';

/**
 * Rule registry
 */
export class RuleRegistry {
  private rules: Map<string, Rule> = new Map();
  private config: Map<string, RuleConfiguration> = new Map();

  constructor() {
    // Register built-in rules
    this.register(missingAuthCheckRule);
  }

  /**
   * Register a rule
   */
  register(rule: Rule): void {
    this.rules.set(rule.id, rule);

    // Set default configuration
    this.config.set(rule.id, {
      enabled: true,
      severity: rule.severity,
    });
  }

  /**
   * Configure a rule
   */
  configure(
    ruleId: string,
    config: {
      enabled?: boolean;
      severity?: FindingSeverity;
      options?: Record<string, unknown>;
    }
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

  /**
   * Get all enabled rules
   */
  getEnabledRules(): Array<{ rule: Rule; config: RuleConfiguration }> {
    const enabled: Array<{ rule: Rule; config: RuleConfiguration }> = [];

    for (const [ruleId, config] of this.config.entries()) {
      if (config.enabled) {
        const rule = this.rules.get(ruleId);
        if (rule) {
          enabled.push({ rule, config });
        }
      }
    }

    return enabled;
  }

  /**
   * Get all rule IDs
   */
  getAllRuleIds(): string[] {
    return Array.from(this.rules.keys());
  }

  /**
   * Apply configuration from user config
   */
  applyConfig(
    userConfig: Record<
      string,
      { enabled?: boolean; severity?: FindingSeverity; options?: Record<string, unknown> }
    >
  ): void {
    for (const [ruleId, ruleConfig] of Object.entries(userConfig)) {
      this.configure(ruleId, ruleConfig);
    }
  }
}
