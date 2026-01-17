import React from 'react';

export interface ConfirmDialogProps {
  open: boolean;
  title: string;
  message: string;
  details?: string[];
  confirmLabel?: string;
  cancelLabel?: string;
  onConfirm: () => void;
  onCancel: () => void;
  destructive?: boolean;
}

export function ConfirmDialog({
  open,
  title,
  message,
  details,
  confirmLabel = 'Confirm',
  cancelLabel = 'Cancel',
  onConfirm,
  onCancel,
  destructive = false,
}: ConfirmDialogProps) {
  if (!open) return null;

  return (
    <div className="confirm-dialog-overlay" onClick={onCancel}>
      <div className="confirm-dialog" onClick={(e) => e.stopPropagation()}>
        <div className="dialog-header">
          <h3 className="dialog-title">{title}</h3>
        </div>

        <div className="dialog-content">
          <p className="dialog-message">{message}</p>

          {details && details.length > 0 && (
            <div className="dialog-details">
              <ul>
                {details.map((detail, index) => (
                  <li key={index}>{detail}</li>
                ))}
              </ul>
            </div>
          )}
        </div>

        <div className="dialog-actions">
          <button
            className="dialog-button cancel-button"
            onClick={onCancel}
          >
            {cancelLabel}
          </button>
          <button
            className={`dialog-button confirm-button ${destructive ? 'destructive' : ''}`}
            onClick={onConfirm}
          >
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}
