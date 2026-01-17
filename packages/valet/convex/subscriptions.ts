import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

/**
 * Convex Subscription Mutations for Valet MVP
 *
 * These mutations handle subscription management and llm-proxy key provisioning.
 */

/**
 * Activate a paid subscription
 *
 * Called when user completes payment (e.g., via Stripe webhook)
 */
export const activateSubscription = mutation({
  args: {
    userId: v.id("users"),
    stripeCustomerId: v.string(),
    stripeSubscriptionId: v.string(),
  },
  handler: async (ctx, args) => {
    const { userId, stripeCustomerId, stripeSubscriptionId } = args;

    const subscription = await ctx.db
      .query("subscriptions")
      .withIndex("by_userId", (q) => q.eq("userId", userId))
      .first();

    if (!subscription) {
      throw new Error("User subscription not found");
    }

    // Activate subscription for 1 year
    const subscriptionStartedAt = Date.now();
    const subscriptionEndsAt = subscriptionStartedAt + 365 * 24 * 60 * 60 * 1000; // 1 year

    await ctx.db.patch(subscription._id, {
      status: "active",
      subscriptionStartedAt,
      subscriptionEndsAt,
      stripeCustomerId,
      stripeSubscriptionId,
      updatedAt: Date.now(),
    });

    return {
      status: "active",
      subscriptionEndsAt,
    };
  },
});

/**
 * Cancel a subscription
 *
 * Called when user cancels their subscription or payment fails
 */
export const cancelSubscription = mutation({
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
      throw new Error("User subscription not found");
    }

    await ctx.db.patch(subscription._id, {
      status: "cancelled",
      updatedAt: Date.now(),
    });

    return {
      status: "cancelled",
    };
  },
});

/**
 * Renew a subscription
 *
 * Called when user renews their subscription (e.g., via Stripe webhook)
 */
export const renewSubscription = mutation({
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
      throw new Error("User subscription not found");
    }

    // Extend subscription by 1 year from current end date
    const currentEndDate = subscription.subscriptionEndsAt || Date.now();
    const newEndDate = currentEndDate + 365 * 24 * 60 * 60 * 1000; // 1 year

    await ctx.db.patch(subscription._id, {
      status: "active",
      subscriptionEndsAt: newEndDate,
      updatedAt: Date.now(),
    });

    return {
      status: "active",
      subscriptionEndsAt: newEndDate,
    };
  },
});

/**
 * Check if user has active access (trial or paid)
 *
 * This query determines if the user can use Valet's features
 */
export const hasActiveAccess = query({
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
      return false;
    }

    // Check if trial is still active
    if (subscription.status === "trial") {
      if (subscription.trialEndsAt && Date.now() < subscription.trialEndsAt) {
        return true;
      }
      // Trial expired
      return false;
    }

    // Check if paid subscription is active
    if (subscription.status === "active") {
      if (subscription.subscriptionEndsAt && Date.now() < subscription.subscriptionEndsAt) {
        return true;
      }
      // Subscription expired
      return false;
    }

    // Cancelled or expired
    return false;
  },
});

/**
 * Provision a new llm-proxy API key
 *
 * This mutation creates a new API key for the user (e.g., if they lost their old one)
 */
export const provisionApiKey = mutation({
  args: {
    userId: v.id("users"),
  },
  handler: async (ctx, args) => {
    const { userId } = args;

    // Check if user already has an API key
    const existingKey = await ctx.db
      .query("llmProxyKeys")
      .withIndex("by_userId", (q) => q.eq("userId", userId))
      .first();

    if (existingKey) {
      // Return existing key instead of creating a duplicate
      return {
        apiKey: existingKey.apiKey,
        createdAt: existingKey.createdAt,
      };
    }

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
      apiKey,
      createdAt: Date.now(),
    };
  },
});

/**
 * Revoke an llm-proxy API key
 *
 * This mutation deletes the user's API key (e.g., if compromised)
 */
export const revokeApiKey = mutation({
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

    await ctx.db.delete(llmProxyKey._id);

    return {
      success: true,
    };
  },
});

/**
 * Rotate an llm-proxy API key
 *
 * This mutation generates a new API key and deletes the old one
 */
export const rotateApiKey = mutation({
  args: {
    userId: v.id("users"),
  },
  handler: async (ctx, args) => {
    const { userId } = args;

    // Delete old key if it exists
    const existingKey = await ctx.db
      .query("llmProxyKeys")
      .withIndex("by_userId", (q) => q.eq("userId", userId))
      .first();

    if (existingKey) {
      await ctx.db.delete(existingKey._id);
    }

    // Generate a new API key
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
      apiKey,
      createdAt: Date.now(),
    };
  },
});

/**
 * Get subscription billing info
 *
 * This query retrieves Stripe customer and subscription IDs for billing portal
 */
export const getBillingInfo = query({
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

    return {
      stripeCustomerId: subscription.stripeCustomerId,
      stripeSubscriptionId: subscription.stripeSubscriptionId,
      status: subscription.status,
    };
  },
});
