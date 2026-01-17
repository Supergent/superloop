import '@testing-library/jest-dom';
import { vi } from 'vitest';

// Mock storage for settings and keychain
export const mockSettings: Record<string, string> = {};
export const mockKeychain: Record<string, string> = {};
export const mockMonitoringStatus: any = null;
export const mockLocalStorage: Record<string, string> = {};

// Mock Tauri invoke function
const mockInvoke = vi.fn(async (cmd: string, args?: any) => {
  // Settings commands
  if (cmd === 'get_setting_command') {
    return args.key in mockSettings ? mockSettings[args.key] : null;
  }
  if (cmd === 'set_setting_command') {
    mockSettings[args.key] = args.value;
    return undefined;
  }
  if (cmd === 'delete_setting_command') {
    delete mockSettings[args.key];
    return undefined;
  }
  if (cmd === 'get_all_settings_command') {
    const settings = { ...mockSettings };
    // If no settings exist, return defaults
    if (Object.keys(settings).length === 0) {
      return {
        voiceEnabled: 'true',
        monitoringFrequency: '30',
        notificationMode: 'critical',
        autoStart: 'false',
      };
    }
    return settings;
  }

  // Keychain commands
  if (cmd === 'store_key_command') {
    mockKeychain[args.keyName] = args.keyValue;
    return undefined;
  }
  if (cmd === 'get_key_command') {
    return mockKeychain[args.keyName] || null;
  }
  if (cmd === 'delete_key_command') {
    delete mockKeychain[args.keyName];
    return undefined;
  }
  if (cmd === 'has_key_command') {
    return args.keyName in mockKeychain;
  }

  // Monitoring commands
  if (cmd === 'get_cached_status') {
    return mockMonitoringStatus;
  }
  if (cmd === 'trigger_status_check') {
    return undefined;
  }
  if (cmd === 'update_monitoring_config') {
    return undefined;
  }

  // Permissions commands
  if (cmd === 'check_permissions_command') {
    return {
      microphone: true,
      fullDiskAccess: true,
      accessibility: true,
    };
  }
  if (cmd === 'request_microphone_permission_command') {
    return true;
  }
  if (cmd === 'open_system_preferences_command') {
    return undefined;
  }

  // Workspace commands
  if (cmd === 'workspace_path') {
    return '/mock/workspace/path';
  }
  if (cmd === 'ensure_workspace_command') {
    return undefined;
  }

  // Mole commands
  if (cmd === 'ensure_mole_installed_command') {
    return true;
  }

  // Audit commands
  if (cmd === 'log_audit_event') {
    return undefined;
  }
  if (cmd === 'get_audit_events') {
    return [];
  }
  if (cmd === 'clear_audit_log_command') {
    return undefined;
  }

  // Auto-start commands
  if (cmd === 'set_autostart') {
    return undefined;
  }
  if (cmd === 'is_autostart_enabled') {
    return false;
  }

  // Default: return empty object
  return {};
});

// Mock Tauri event system
const mockListen = vi.fn(async (event: string, handler: (event: any) => void) => {
  return () => {}; // Return unlisten function
});

const mockEmit = vi.fn(async (event: string, payload?: any) => {
  return undefined;
});

// Set up global Tauri mocks
global.window = global.window || {};
(global.window as any).__TAURI_INTERNALS__ = {
  transformCallback: (callback: any) => callback,
  invoke: mockInvoke,
};

// Mock @tauri-apps/api modules
vi.mock('@tauri-apps/api/core', () => ({
  invoke: mockInvoke,
}));

vi.mock('@tauri-apps/api/tauri', () => ({
  invoke: mockInvoke,
}));

vi.mock('@tauri-apps/api/event', () => ({
  listen: mockListen,
  emit: mockEmit,
}));

vi.mock('@tauri-apps/plugin-global-shortcut', () => ({
  register: vi.fn(async (shortcut: string, handler: () => void) => {
    // Store the handler for testing if needed
    return undefined;
  }),
  unregister: vi.fn(async (shortcut: string) => {
    return undefined;
  }),
  isRegistered: vi.fn(async (shortcut: string) => {
    return false;
  }),
  unregisterAll: vi.fn(async () => {
    return undefined;
  }),
}));

// Mock localStorage
const localStorageMock = {
  getItem: (key: string) => mockLocalStorage[key] || null,
  setItem: (key: string, value: string) => {
    mockLocalStorage[key] = value;
  },
  removeItem: (key: string) => {
    delete mockLocalStorage[key];
  },
  clear: () => {
    Object.keys(mockLocalStorage).forEach(key => delete mockLocalStorage[key]);
  },
  get length() {
    return Object.keys(mockLocalStorage).length;
  },
  key: (index: number) => {
    const keys = Object.keys(mockLocalStorage);
    return keys[index] || null;
  },
};

Object.defineProperty(global, 'localStorage', {
  value: localStorageMock,
  writable: true,
});

// Export mocks for test access
export { mockInvoke, mockListen, mockEmit };

// Reset mocks before each test
beforeEach(() => {
  Object.keys(mockSettings).forEach(key => delete mockSettings[key]);
  Object.keys(mockKeychain).forEach(key => delete mockKeychain[key]);
  Object.keys(mockLocalStorage).forEach(key => delete mockLocalStorage[key]);
  mockInvoke.mockClear();
  mockListen.mockClear();
  mockEmit.mockClear();
});
