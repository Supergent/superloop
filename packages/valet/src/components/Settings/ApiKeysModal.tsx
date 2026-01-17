import React, { useState } from 'react';
import { useApiKeys } from '../../hooks/useApiKeys';
import { KEY_NAMES, type KeyName } from '../../lib/keys';

interface ApiKeysModalProps {
  isOpen: boolean;
  onClose: () => void;
  onKeysChanged?: () => void;
}

interface KeyInputState {
  assemblyAi: string;
  vapiPublic: string;
  llmProxy: string;
}

export function ApiKeysModal({ isOpen, onClose, onKeysChanged }: ApiKeysModalProps) {
  const { keys, status, loading, error, saveKey, removeKey } = useApiKeys({ enabled: isOpen });

  // Local state for input values (masked by default)
  const [inputValues, setInputValues] = useState<KeyInputState>({
    assemblyAi: '',
    vapiPublic: '',
    llmProxy: '',
  });

  // Track which fields are being revealed
  const [revealed, setRevealed] = useState<{
    assemblyAi: boolean;
    vapiPublic: boolean;
    llmProxy: boolean;
  }>({
    assemblyAi: false,
    vapiPublic: false,
    llmProxy: false,
  });

  // Track which fields are being edited
  const [editing, setEditing] = useState<{
    assemblyAi: boolean;
    vapiPublic: boolean;
    llmProxy: boolean;
  }>({
    assemblyAi: false,
    vapiPublic: false,
    llmProxy: false,
  });

  const [saveError, setSaveError] = useState<string | null>(null);
  const [saveSuccess, setSaveSuccess] = useState<string | null>(null);

  // Reset local state when modal closes
  React.useEffect(() => {
    if (!isOpen) {
      // Clear all input values
      setInputValues({
        assemblyAi: '',
        vapiPublic: '',
        llmProxy: '',
      });
      // Hide all revealed keys
      setRevealed({
        assemblyAi: false,
        vapiPublic: false,
        llmProxy: false,
      });
      // Clear editing states
      setEditing({
        assemblyAi: false,
        vapiPublic: false,
        llmProxy: false,
      });
      // Clear error and success messages
      setSaveError(null);
      setSaveSuccess(null);
    }
  }, [isOpen]);

  if (!isOpen) {
    return null;
  }

  const handleInputChange = (field: keyof KeyInputState, value: string) => {
    setInputValues((prev) => ({
      ...prev,
      [field]: value,
    }));
    setSaveError(null);
    setSaveSuccess(null);
  };

  const toggleReveal = (field: keyof typeof revealed) => {
    setRevealed((prev) => ({
      ...prev,
      [field]: !prev[field],
    }));
  };

  const startEditing = (field: keyof typeof editing) => {
    setEditing((prev) => ({
      ...prev,
      [field]: true,
    }));
    // Clear the input when starting to edit
    setInputValues((prev) => ({
      ...prev,
      [field]: '',
    }));
    setSaveError(null);
    setSaveSuccess(null);
  };

  const cancelEditing = (field: keyof typeof editing) => {
    setEditing((prev) => ({
      ...prev,
      [field]: false,
    }));
    setInputValues((prev) => ({
      ...prev,
      [field]: '',
    }));
    setSaveError(null);
    setSaveSuccess(null);
  };

  const handleSave = async (field: keyof KeyInputState) => {
    const value = inputValues[field].trim();
    if (!value) {
      setSaveError('API key cannot be empty');
      return;
    }

    setSaveError(null);
    setSaveSuccess(null);

    try {
      let keyName: KeyName;
      switch (field) {
        case 'assemblyAi':
          keyName = KEY_NAMES.ASSEMBLY_AI;
          break;
        case 'vapiPublic':
          keyName = KEY_NAMES.VAPI_PUBLIC;
          break;
        case 'llmProxy':
          keyName = KEY_NAMES.LLM_PROXY;
          break;
      }

      await saveKey(keyName, value);
      setSaveSuccess(`${getKeyLabel(field)} saved successfully`);
      setEditing((prev) => ({ ...prev, [field]: false }));
      setInputValues((prev) => ({ ...prev, [field]: '' }));

      // Notify parent that keys have changed
      onKeysChanged?.();

      // Emit custom event for any listeners (e.g., App.tsx)
      window.dispatchEvent(new CustomEvent('api-keys-changed'));
    } catch (err) {
      setSaveError(err instanceof Error ? err.message : 'Failed to save API key');
    }
  };

  const handleDelete = async (field: keyof KeyInputState) => {
    if (!confirm(`Are you sure you want to delete the ${getKeyLabel(field)}?`)) {
      return;
    }

    setSaveError(null);
    setSaveSuccess(null);

    try {
      let keyName: KeyName;
      switch (field) {
        case 'assemblyAi':
          keyName = KEY_NAMES.ASSEMBLY_AI;
          break;
        case 'vapiPublic':
          keyName = KEY_NAMES.VAPI_PUBLIC;
          break;
        case 'llmProxy':
          keyName = KEY_NAMES.LLM_PROXY;
          break;
      }

      await removeKey(keyName);
      setSaveSuccess(`${getKeyLabel(field)} deleted successfully`);

      // Notify parent that keys have changed
      onKeysChanged?.();

      // Emit custom event for any listeners (e.g., App.tsx)
      window.dispatchEvent(new CustomEvent('api-keys-changed'));
    } catch (err) {
      setSaveError(err instanceof Error ? err.message : 'Failed to delete API key');
    }
  };

  const getKeyLabel = (field: keyof KeyInputState): string => {
    switch (field) {
      case 'assemblyAi':
        return 'AssemblyAI API Key';
      case 'vapiPublic':
        return 'Vapi Public Key';
      case 'llmProxy':
        return 'LLM Proxy API Key';
    }
  };

  const getKeyDescription = (field: keyof KeyInputState): string => {
    switch (field) {
      case 'assemblyAi':
        return 'Required for speech-to-text functionality';
      case 'vapiPublic':
        return 'Required for text-to-speech functionality';
      case 'llmProxy':
        return 'Required for Claude agent integration';
    }
  };

  const maskKey = (key: string | null): string => {
    if (!key) return '';
    if (key.length <= 8) return '•'.repeat(key.length);
    return key.substring(0, 4) + '•'.repeat(key.length - 8) + key.substring(key.length - 4);
  };

  const renderKeyField = (field: keyof KeyInputState) => {
    const hasKey = status[field];
    const isEditing = editing[field];
    const isRevealed = revealed[field];

    return (
      <div className="api-key-field" key={field}>
        <div className="api-key-header">
          <label className="api-key-label">{getKeyLabel(field)}</label>
          <span className="api-key-description">{getKeyDescription(field)}</span>
        </div>

        {!isEditing && hasKey && (
          <div className="api-key-display">
            <div className="api-key-value">
              {isRevealed ? keys[field] : maskKey(keys[field])}
            </div>
            <div className="api-key-actions">
              <button
                className="api-key-button secondary"
                onClick={() => toggleReveal(field)}
                title={isRevealed ? 'Hide' : 'Reveal'}
              >
                {isRevealed ? '👁️' : '👁️‍🗨️'}
              </button>
              <button
                className="api-key-button secondary"
                onClick={() => startEditing(field)}
              >
                Edit
              </button>
              <button
                className="api-key-button danger"
                onClick={() => handleDelete(field)}
              >
                Delete
              </button>
            </div>
          </div>
        )}

        {(!hasKey || isEditing) && (
          <div className="api-key-input-group">
            <input
              type="text"
              className="api-key-input"
              placeholder={`Enter ${getKeyLabel(field)}`}
              value={inputValues[field]}
              onChange={(e) => handleInputChange(field, e.target.value)}
            />
            <div className="api-key-actions">
              <button
                className="api-key-button primary"
                onClick={() => handleSave(field)}
                disabled={loading || !inputValues[field].trim()}
              >
                Save
              </button>
              {isEditing && hasKey && (
                <button
                  className="api-key-button secondary"
                  onClick={() => cancelEditing(field)}
                >
                  Cancel
                </button>
              )}
            </div>
          </div>
        )}
      </div>
    );
  };

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-content api-keys-modal" onClick={(e) => e.stopPropagation()}>
        <div className="modal-header">
          <h2>Manage API Keys</h2>
          <button className="close-button" onClick={onClose}>
            ✕
          </button>
        </div>

        <div className="modal-body">
          {error && <div className="api-keys-error">{error}</div>}
          {saveError && <div className="api-keys-error">{saveError}</div>}
          {saveSuccess && <div className="api-keys-success">{saveSuccess}</div>}

          <div className="api-keys-info">
            <p>
              API keys are stored securely in your macOS Keychain. They are required
              for voice and AI features to work properly.
            </p>
          </div>

          <div className="api-keys-fields">
            {renderKeyField('assemblyAi')}
            {renderKeyField('vapiPublic')}
            {renderKeyField('llmProxy')}
          </div>
        </div>

        <div className="modal-footer">
          <button className="modal-button secondary" onClick={onClose}>
            Close
          </button>
        </div>
      </div>
    </div>
  );
}
