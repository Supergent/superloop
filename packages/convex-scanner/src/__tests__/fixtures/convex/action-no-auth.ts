import { action } from './_generated/server';

export const sendEmail = action({
  args: {},
  handler: async (ctx: any) => {
    return { ok: true, context: ctx };
  },
});
