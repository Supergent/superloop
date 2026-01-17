import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

/**
 * Convex Schema for Valet MVP
 *
 * Tables:
 * - users: User accounts (managed by Better-Auth)
 * - subscriptions: Subscription status and trial tracking
 * - llmProxyKeys: Per-user API keys for llm-proxy.super.gent
 */

export default defineSchema({
  /**
   * Users table (managed by Better-Auth)
   * Better-Auth will create and manage this table
   */
  users: defineTable({
    email: v.string(),
    emailVerified: v.optional(v.boolean()),
    name: v.optional(v.string()),
    image: v.optional(v.string()),
    createdAt: v.number(),
    updatedAt: v.number(),
  }).index("by_email", ["email"]),

  /**
   * Accounts table (managed by Better-Auth for OAuth providers)
   */
  accounts: defineTable({
    userId: v.id("users"),
    provider: v.string(),
    providerAccountId: v.string(),
    refreshToken: v.optional(v.string()),
    accessToken: v.optional(v.string()),
    expiresAt: v.optional(v.number()),
    createdAt: v.number(),
    updatedAt: v.number(),
  })
    .index("by_userId", ["userId"])
    .index("by_provider_and_accountId", ["provider", "providerAccountId"]),

  /**
   * Sessions table (managed by Better-Auth)
   */
  sessions: defineTable({
    userId: v.id("users"),
    sessionToken: v.string(),
    expires: v.number(),
  })
    .index("by_sessionToken", ["sessionToken"])
    .index("by_userId", ["userId"]),

  /**
   * Verification tokens table (managed by Better-Auth for email verification)
   */
  verificationTokens: defineTable({
    identifier: v.string(),
    token: v.string(),
    expires: v.number(),
  })
    .index("by_identifier", ["identifier"])
    .index("by_token", ["token"]),

  /**
   * Subscriptions table
   * Tracks trial status and paid subscriptions
   */
  subscriptions: defineTable({
    userId: v.id("users"),
    status: v.union(
      v.literal("trial"),
      v.literal("active"),
      v.literal("expired"),
      v.literal("cancelled")
    ),
    trialStartedAt: v.optional(v.number()), // Timestamp when trial started
    trialEndsAt: v.optional(v.number()), // Timestamp when trial ends (7 days from start)
    subscriptionStartedAt: v.optional(v.number()), // Timestamp when paid subscription started
    subscriptionEndsAt: v.optional(v.number()), // Timestamp when paid subscription ends (1 year from start)
    stripeCustomerId: v.optional(v.string()), // Stripe customer ID for billing
    stripeSubscriptionId: v.optional(v.string()), // Stripe subscription ID
    createdAt: v.number(),
    updatedAt: v.number(),
  })
    .index("by_userId", ["userId"])
    .index("by_status", ["status"])
    .index("by_stripeCustomerId", ["stripeCustomerId"]),

  /**
   * LLM Proxy Keys table
   * Stores per-user API keys for llm-proxy.super.gent access
   */
  llmProxyKeys: defineTable({
    userId: v.id("users"),
    apiKey: v.string(), // Encrypted API key for llm-proxy
    createdAt: v.number(),
    lastUsedAt: v.optional(v.number()), // Track last usage for analytics
    usageCount: v.optional(v.number()), // Track total usage count
  })
    .index("by_userId", ["userId"])
    .index("by_apiKey", ["apiKey"]),
});
