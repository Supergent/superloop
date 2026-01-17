/**
 * Better-Auth Client Setup for Valet MVP
 *
 * This module provides authentication helpers using Better-Auth.
 */

import { createAuthClient } from "better-auth/client";

/**
 * Auth API base URL
 *
 * In production, this should point to the auth API endpoint.
 * For development, use the local dev server URL.
 */
const AUTH_BASE_URL = import.meta.env.VITE_AUTH_BASE_URL || "http://localhost:3000";

/**
 * Better-Auth client instance
 *
 * This client handles authentication flows (signup, signin, signout).
 */
export const authClient = createAuthClient({
  baseURL: AUTH_BASE_URL,
});

/**
 * Authentication state type
 */
export interface AuthState {
  user: {
    id: string;
    email: string;
    name?: string;
  } | null;
  isLoading: boolean;
  error: Error | null;
}

/**
 * Sign up a new user with email and password
 */
export async function signUp(email: string, password: string, name?: string) {
  try {
    const result = await authClient.signUp.email({
      email,
      password,
      name,
    });

    if (!result.data) {
      throw new Error(result.error?.message || "Sign up failed");
    }

    return result.data;
  } catch (error) {
    console.error("Sign up error:", error);
    throw error;
  }
}

/**
 * Sign in an existing user with email and password
 */
export async function signIn(email: string, password: string) {
  try {
    const result = await authClient.signIn.email({
      email,
      password,
    });

    if (!result.data) {
      throw new Error(result.error?.message || "Sign in failed");
    }

    return result.data;
  } catch (error) {
    console.error("Sign in error:", error);
    throw error;
  }
}

/**
 * Sign out the current user
 */
export async function signOut() {
  try {
    await authClient.signOut();
  } catch (error) {
    console.error("Sign out error:", error);
    throw error;
  }
}

/**
 * Get the current authenticated user session
 */
export async function getSession() {
  try {
    const session = await authClient.getSession();
    return session;
  } catch (error) {
    console.error("Get session error:", error);
    return null;
  }
}

/**
 * Check if user is authenticated
 */
export async function isAuthenticated(): Promise<boolean> {
  const session = await getSession();
  return !!session?.user;
}

/**
 * Get current user ID if authenticated
 */
export async function getCurrentUserId(): Promise<string | null> {
  const session = await getSession();
  return session?.user?.id || null;
}
