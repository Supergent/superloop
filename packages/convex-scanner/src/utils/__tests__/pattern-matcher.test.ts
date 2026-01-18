import { describe, it, expect } from 'vitest';
import { matchesPattern } from '../pattern-matcher.js';

describe('pattern-matcher', () => {
  it('matches glob patterns', () => {
    expect(matchesPattern('signup', ['signup*'])).toBe(true);
    expect(matchesPattern('signupWithEmail', ['signup*'])).toBe(true);
  });

  it('matches exact patterns', () => {
    expect(matchesPattern('login', ['signup*', 'login'])).toBe(true);
  });

  it('matches case-insensitively', () => {
    expect(matchesPattern('SignUpWithEmail', ['signup*'])).toBe(true);
  });

  it('returns false when no patterns match', () => {
    expect(matchesPattern('resetPassword', ['login', 'signup*'])).toBe(false);
  });
});
