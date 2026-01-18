import { action } from './_generated/server';

export const securedAction = action({
  args: {},
  handler: async (ctx: any) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) {
      throw new Error('Unauthenticated');
    }

    return { ok: true, userId: identity.subject };
  },
});
