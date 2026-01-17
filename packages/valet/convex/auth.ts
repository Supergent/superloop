import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

/**
 * Convex Auth Mutations for Valet MVP
 *
 * These mutations handle user authentication and trial management.
 * They work in conjunction with Better-Auth for authentication.
 */

/**
 * Sign up a new user and start their trial
 *
 * This mutation is called after Better-Auth creates the user account.
 * It initializes the subscription and provisions an llm-proxy API key.
 */
export const signUp = mutation({
  args: {
    userId: v.id("users"),
    email: v.string(),
  },
  handler: async (ctx, args) => {
    const { userId, email } = args;

    // Check if subscription already exists (shouldn't happen, but guard against duplicates)
    const existingSubscription = await ctx.db
      .query("subscriptions")
      .withIndex("by_userId", (q) => q.eq("userId", userId))
      .first();

    if (existingSubscription) {
      throw new Error("User already has a subscription");
    }

    // Create trial subscription (7 days)
    const trialStartedAt = Date.now();
    const trialEndsAt = trialStartedAt + 7 * 24 * 60 * 60 * 1000; // 7 days

    const subscriptionId = await ctx.db.insert("subscriptions", {
      userId,
      status: "trial",
      trialStartedAt,
      trialEndsAt,
      createdAt: Date.now(),
      updatedAt: Date.now(),
    });

    // Generate a unique llm-proxy API key for this user
    // Format: valet_<userId>_<randomString>
    const randomPart = Math.random().toString(36).substring(2, 15) +
      Math.random().toString(36).substring(2, 15);
    const apiKey = `valet_${userId}_${randomPart}`;

    await ctx.db.insert("llmProxyKeys", {
      userId,
      apiKey,
      createdAt: Date.now(),
      usageCount: 0,
    });

    return {
      subscriptionId,
      status: "trial",
      trialEndsAt,
      apiKey,
    };
  },
});

/**
 * Sign in an existing user
 *
 * This query retrieves the user's subscription status and API key.
 */
export const signIn = query({
  args: {
    userId: v.id("users"),
  },
  handler: async (ctx, args) => {
    const { userId } = args;

    // Get subscription
    const subscription = await ctx.db
      .query("subscriptions")
      .withIndex("by_userId", (q) => q.eq("userId", userId))
      .first();

    if (!subscription) {
      throw new Error("User subscription not found");
    }

    // Get llm-proxy API key
    const llmProxyKey = await ctx.db
      .query("llmProxyKeys")
      .withIndex("by_userId", (q) => q.eq("userId", userId))
      .first();

    if (!llmProxyKey) {
      throw new Error("User API key not found");
    }

    // Update last used timestamp
    await ctx.db.patch(llmProxyKey._id, {
      lastUsedAt: Date.now(),
    });

    return {
      subscription: {
        status: subscription.status,
        trialEndsAt: subscription.trialEndsAt,
        subscriptionEndsAt: subscription.subscriptionEndsAt,
      },
      apiKey: llmProxyKey.apiKey,
    };
  },
});

/**
 * Get current user's subscription status
 */
export const getSubscriptionStatus = query({
  args: {
    userId: v.id("users"),
  },
  handler: async (ctx, args) => {
    const { userId } = args;

    const subscription = await ctx.db
      .query("subscriptions")
      .withIndex("by_userId", (q) => q.eq("userId", userId))
      .first();

    if (!subscription) {
      return null;
    }

    // Auto-expire trial if needed
    if (subscription.status === "trial" && subscription.trialEndsAt) {
      if (Date.now() > subscription.trialEndsAt) {
        await ctx.db.patch(subscription._id, {
          status: "expired",
          updatedAt: Date.now(),
        });
        return {
          status: "expired",
          trialEndsAt: subscription.trialEndsAt,
        };
      }
    }

    return {
      status: subscription.status,
      trialStartedAt: subscription.trialStartedAt,
      trialEndsAt: subscription.trialEndsAt,
      subscriptionStartedAt: subscription.subscriptionStartedAt,
      subscriptionEndsAt: subscription.subscriptionEndsAt,
    };
  },
});

/**
 * Get current user's llm-proxy API key
 */
export const getApiKey = query({
  args: {
    userId: v.id("users"),
  },
  handler: async (ctx, args) => {
    const { userId } = args;

    const llmProxyKey = await ctx.db
      .query("llmProxyKeys")
      .withIndex("by_userId", (q) => q.eq("userId", userId))
      .first();

    if (!llmProxyKey) {
      return null;
    }

    // Update last used timestamp
    await ctx.db.patch(llmProxyKey._id, {
      lastUsedAt: Date.now(),
    });

    return {
      apiKey: llmProxyKey.apiKey,
      createdAt: llmProxyKey.createdAt,
      lastUsedAt: llmProxyKey.lastUsedAt,
      usageCount: llmProxyKey.usageCount,
    };
  },
});

/**
 * Track API key usage
 */
export const trackApiKeyUsage = mutation({
  args: {
    userId: v.id("users"),
  },
  handler: async (ctx, args) => {
    const { userId } = args;

    const llmProxyKey = await ctx.db
      .query("llmProxyKeys")
      .withIndex("by_userId", (q) => q.eq("userId", userId))
      .first();

    if (!llmProxyKey) {
      throw new Error("User API key not found");
    }

    await ctx.db.patch(llmProxyKey._id, {
      lastUsedAt: Date.now(),
      usageCount: (llmProxyKey.usageCount || 0) + 1,
    });
  },
});
