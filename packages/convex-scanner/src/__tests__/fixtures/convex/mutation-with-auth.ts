import { mutation, type MutationCtx } from './_generated/server';
import { v } from 'convex/values';

export const createItem = mutation({
  args: {
    name: v.string(),
  },
  handler: async (ctx: MutationCtx, args: { name: string }) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) {
      throw new Error('Unauthenticated');
    }

    const id = await ctx.db.insert('items', {
      name: args.name,
      userId: identity.subject,
    });
    return id;
  },
});
