import { invoke } from '@tauri-apps/api/core';

/**
 * Key names for storing in macOS Keychain
 */
export const KEY_NAMES = {
  ASSEMBLY_AI: 'assemblyai_api_key',
  VAPI_PUBLIC: 'vapi_public_key',
  LLM_PROXY: 'llm_proxy_api_key',
} as const;

/**
 * Legacy key names for backward compatibility
 */
export const LEGACY_KEY_NAMES = {
  ASSEMBLY_AI: 'assemblyai',
  VAPI_PUBLIC: 'vapi-public',
  LLM_PROXY: 'llm-proxy',
} as const;

export type KeyName = typeof KEY_NAMES[keyof typeof KEY_NAMES];

/**
 * Store a key in the macOS Keychain
 */
export async function storeKey(keyName: KeyName, keyValue: string): Promise<void> {
  try {
    await invoke('store_key_command', { keyName, keyValue });
  } catch (error) {
    console.error(`Failed to store key ${keyName}:`, error);
    throw error;
  }
}

/**
 * Get the legacy key name for a given current key name
 */
function getLegacyKeyName(keyName: KeyName): string | null {
  switch (keyName) {
    case KEY_NAMES.ASSEMBLY_AI:
      return LEGACY_KEY_NAMES.ASSEMBLY_AI;
    case KEY_NAMES.VAPI_PUBLIC:
      return LEGACY_KEY_NAMES.VAPI_PUBLIC;
    case KEY_NAMES.LLM_PROXY:
      return LEGACY_KEY_NAMES.LLM_PROXY;
    default:
      return null;
  }
}

/**
 * Retrieve a key from the macOS Keychain
 * Tries current key name first, then falls back to legacy name
 * @throws Error if keychain access fails
 */
export async function getKey(keyName: KeyName): Promise<string | null> {
  // Try current key name first
  const value = await invoke<string | null>('get_key_command', { keyName });
  if (value) {
    return value;
  }

  // Fall back to legacy key name
  const legacyKeyName = getLegacyKeyName(keyName);
  if (legacyKeyName) {
    const legacyValue = await invoke<string | null>('get_key_command', { keyName: legacyKeyName });
    return legacyValue;
  }

  return null;
}

/**
 * Delete a key from the macOS Keychain
 */
export async function deleteKey(keyName: KeyName): Promise<void> {
  try {
    await invoke('delete_key_command', { keyName });
  } catch (error) {
    console.error(`Failed to delete key ${keyName}:`, error);
    throw error;
  }
}

/**
 * Check if a key exists in the macOS Keychain
 * Checks both current and legacy key names
 * @throws Error if keychain access fails
 */
export async function hasKey(keyName: KeyName): Promise<boolean> {
  // Check current key name first
  const exists = await invoke<boolean>('has_key_command', { keyName });
  if (exists) {
    return true;
  }

  // Check legacy key name
  const legacyKeyName = getLegacyKeyName(keyName);
  if (legacyKeyName) {
    const legacyExists = await invoke<boolean>('has_key_command', { keyName: legacyKeyName });
    return legacyExists;
  }

  return false;
}

/**
 * Get all API keys
 */
export async function getAllKeys(): Promise<{
  assemblyAi: string | null;
  vapiPublic: string | null;
  llmProxy: string | null;
}> {
  const [assemblyAi, vapiPublic, llmProxy] = await Promise.all([
    getKey(KEY_NAMES.ASSEMBLY_AI),
    getKey(KEY_NAMES.VAPI_PUBLIC),
    getKey(KEY_NAMES.LLM_PROXY),
  ]);

  return {
    assemblyAi,
    vapiPublic,
    llmProxy,
  };
}

/**
 * Check which keys are configured
 */
export async function getKeyStatus(): Promise<{
  assemblyAi: boolean;
  vapiPublic: boolean;
  llmProxy: boolean;
}> {
  const [assemblyAi, vapiPublic, llmProxy] = await Promise.all([
    hasKey(KEY_NAMES.ASSEMBLY_AI),
    hasKey(KEY_NAMES.VAPI_PUBLIC),
    hasKey(KEY_NAMES.LLM_PROXY),
  ]);

  return {
    assemblyAi,
    vapiPublic,
    llmProxy,
  };
}

/**
 * Store per-user llm-proxy key after authentication
 * This is called after successful auth to persist the provisioned API key
 */
export async function storeLlmProxyKeyAfterAuth(apiKey: string): Promise<void> {
  try {
    await storeKey(KEY_NAMES.LLM_PROXY, apiKey);
    console.log('Per-user llm-proxy key stored in Keychain');
  } catch (error) {
    console.error('Failed to store per-user llm-proxy key:', error);
    throw error;
  }
}
