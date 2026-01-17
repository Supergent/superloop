import { useState, useEffect } from 'react';
import { invoke } from '@tauri-apps/api/core';

interface PermissionsProps {
  onNext: () => void;
  onBack: () => void;
}

interface PermissionStatus {
  microphone: boolean;
  fullDiskAccess: boolean;
  accessibility: boolean;
}

export function Permissions({ onNext, onBack }: PermissionsProps) {
  const [permissions, setPermissions] = useState<PermissionStatus>({
    microphone: false,
    fullDiskAccess: false,
    accessibility: false,
  });
  const [isChecking, setIsChecking] = useState(false);

  useEffect(() => {
    checkPermissions();
  }, []);

  const checkPermissions = async () => {
    setIsChecking(true);
    try {
      const status = await invoke<PermissionStatus>('check_permissions_command');
      setPermissions(status);
    } catch (error) {
      console.error('Failed to check permissions:', error);
    } finally {
      setIsChecking(false);
    }
  };

  const requestMicrophone = async () => {
    try {
      await invoke('request_microphone_permission_command');
      await checkPermissions();
    } catch (error) {
      console.error('Failed to request microphone permission:', error);
    }
  };

  const openSystemPreferences = async (pane: 'privacy_microphone' | 'privacy_full_disk_access' | 'privacy_accessibility') => {
    try {
      await invoke('open_system_preferences_command', { pane });
    } catch (error) {
      console.error('Failed to open system preferences:', error);
    }
  };

  const allGranted = permissions.microphone && permissions.fullDiskAccess && permissions.accessibility;

  return (
    <div className="onboarding-screen permissions-screen">
      <div className="onboarding-content">
        <h1>Grant Permissions</h1>
        <p className="subtitle">Valet needs these permissions to function properly</p>

        <div className="permissions-list">
          <div className={`permission-item ${permissions.microphone ? 'granted' : 'pending'}`}>
            <div className="permission-header">
              <div className="permission-icon">🎤</div>
              <div className="permission-info">
                <h3>Microphone Access</h3>
                <p>Required for voice input</p>
              </div>
              <div className="permission-status">
                {permissions.microphone ? '✓' : '○'}
              </div>
            </div>
            {!permissions.microphone && (
              <button className="btn-secondary btn-small" onClick={requestMicrophone}>
                Request Access
              </button>
            )}
          </div>

          <div className={`permission-item ${permissions.fullDiskAccess ? 'granted' : 'pending'}`}>
            <div className="permission-header">
              <div className="permission-icon">💾</div>
              <div className="permission-info">
                <h3>Full Disk Access</h3>
                <p>Required for Mole to scan and clean system files</p>
              </div>
              <div className="permission-status">
                {permissions.fullDiskAccess ? '✓' : '○'}
              </div>
            </div>
            {!permissions.fullDiskAccess && (
              <button
                className="btn-secondary btn-small"
                onClick={() => openSystemPreferences('privacy_full_disk_access')}
              >
                Open System Settings
              </button>
            )}
          </div>

          <div className={`permission-item ${permissions.accessibility ? 'granted' : 'pending'}`}>
            <div className="permission-header">
              <div className="permission-icon">♿</div>
              <div className="permission-info">
                <h3>Accessibility</h3>
                <p>Required for global keyboard shortcut</p>
              </div>
              <div className="permission-status">
                {permissions.accessibility ? '✓' : '○'}
              </div>
            </div>
            {!permissions.accessibility && (
              <button
                className="btn-secondary btn-small"
                onClick={() => openSystemPreferences('privacy_accessibility')}
              >
                Open System Settings
              </button>
            )}
          </div>
        </div>

        <div className="permission-note">
          <p>
            <strong>Note:</strong> After granting permissions in System Settings, please click
            "Refresh" to verify the changes.
          </p>
          <button className="btn-secondary" onClick={checkPermissions} disabled={isChecking}>
            {isChecking ? 'Checking...' : 'Refresh'}
          </button>
        </div>

        <div className="onboarding-actions">
          <button className="btn-secondary" onClick={onBack}>
            Back
          </button>
          <button
            className="btn-primary"
            onClick={onNext}
            disabled={!allGranted}
            title={!allGranted ? 'Please grant all permissions to continue' : ''}
          >
            Continue
          </button>
        </div>
      </div>
    </div>
  );
}
