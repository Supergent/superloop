import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { ConfirmDialog, type ConfirmDialogProps } from '../ConfirmDialog';

describe('ConfirmDialog', () => {
  let mockOnConfirm: ReturnType<typeof vi.fn>;
  let mockOnCancel: ReturnType<typeof vi.fn>;
  let defaultProps: ConfirmDialogProps;

  beforeEach(() => {
    mockOnConfirm = vi.fn();
    mockOnCancel = vi.fn();
    defaultProps = {
      open: true,
      title: 'Test Title',
      message: 'Test message',
      onConfirm: mockOnConfirm,
      onCancel: mockOnCancel,
    };
  });

  describe('Rendering', () => {
    it('should render when open is true', () => {
      render(<ConfirmDialog {...defaultProps} />);

      expect(screen.getByText('Test Title')).toBeInTheDocument();
      expect(screen.getByText('Test message')).toBeInTheDocument();
      expect(screen.getByText('Confirm')).toBeInTheDocument();
      expect(screen.getByText('Cancel')).toBeInTheDocument();
    });

    it('should not render when open is false', () => {
      render(<ConfirmDialog {...defaultProps} open={false} />);

      expect(screen.queryByText('Test Title')).not.toBeInTheDocument();
      expect(screen.queryByText('Test message')).not.toBeInTheDocument();
    });

    it('should render with custom confirm label', () => {
      render(<ConfirmDialog {...defaultProps} confirmLabel="Yes, proceed" />);

      expect(screen.getByText('Yes, proceed')).toBeInTheDocument();
      expect(screen.queryByText('Confirm')).not.toBeInTheDocument();
    });

    it('should render with custom cancel label', () => {
      render(<ConfirmDialog {...defaultProps} cancelLabel="No, go back" />);

      expect(screen.getByText('No, go back')).toBeInTheDocument();
      expect(screen.queryByText('Cancel')).not.toBeInTheDocument();
    });

    it('should render details when provided', () => {
      const details = ['Detail 1', 'Detail 2', 'Detail 3'];
      render(<ConfirmDialog {...defaultProps} details={details} />);

      expect(screen.getByText('Detail 1')).toBeInTheDocument();
      expect(screen.getByText('Detail 2')).toBeInTheDocument();
      expect(screen.getByText('Detail 3')).toBeInTheDocument();
    });

    it('should not render details section when details is empty', () => {
      render(<ConfirmDialog {...defaultProps} details={[]} />);

      const detailsContainer = screen.queryByRole('list');
      expect(detailsContainer).not.toBeInTheDocument();
    });

    it('should not render details section when details is undefined', () => {
      render(<ConfirmDialog {...defaultProps} details={undefined} />);

      const detailsContainer = screen.queryByRole('list');
      expect(detailsContainer).not.toBeInTheDocument();
    });

    it('should apply destructive class when destructive is true', () => {
      render(<ConfirmDialog {...defaultProps} destructive={true} />);

      const confirmButton = screen.getByText('Confirm');
      expect(confirmButton).toHaveClass('destructive');
    });

    it('should not apply destructive class when destructive is false', () => {
      render(<ConfirmDialog {...defaultProps} destructive={false} />);

      const confirmButton = screen.getByText('Confirm');
      expect(confirmButton).not.toHaveClass('destructive');
    });
  });

  describe('User Interactions', () => {
    it('should call onConfirm when confirm button is clicked', async () => {
      const user = userEvent.setup();
      render(<ConfirmDialog {...defaultProps} />);

      const confirmButton = screen.getByText('Confirm');
      await user.click(confirmButton);

      expect(mockOnConfirm).toHaveBeenCalledTimes(1);
      expect(mockOnCancel).not.toHaveBeenCalled();
    });

    it('should call onCancel when cancel button is clicked', async () => {
      const user = userEvent.setup();
      render(<ConfirmDialog {...defaultProps} />);

      const cancelButton = screen.getByText('Cancel');
      await user.click(cancelButton);

      expect(mockOnCancel).toHaveBeenCalledTimes(1);
      expect(mockOnConfirm).not.toHaveBeenCalled();
    });

    it('should call onCancel when clicking overlay', async () => {
      const user = userEvent.setup();
      const { container } = render(<ConfirmDialog {...defaultProps} />);

      const overlay = container.querySelector('.confirm-dialog-overlay');
      expect(overlay).toBeTruthy();

      if (overlay) {
        await user.click(overlay);
        expect(mockOnCancel).toHaveBeenCalledTimes(1);
        expect(mockOnConfirm).not.toHaveBeenCalled();
      }
    });

    it('should not call onCancel when clicking dialog content', async () => {
      const user = userEvent.setup();
      const { container } = render(<ConfirmDialog {...defaultProps} />);

      const dialog = container.querySelector('.confirm-dialog');
      expect(dialog).toBeTruthy();

      if (dialog) {
        await user.click(dialog);
        expect(mockOnCancel).not.toHaveBeenCalled();
        expect(mockOnConfirm).not.toHaveBeenCalled();
      }
    });

    it('should stop propagation when clicking inside dialog', async () => {
      const user = userEvent.setup();
      render(<ConfirmDialog {...defaultProps} />);

      const message = screen.getByText('Test message');
      await user.click(message);

      // Verify that stopPropagation would be called in the actual implementation
      // by ensuring onCancel is not called when clicking inside the dialog
      expect(mockOnCancel).not.toHaveBeenCalled();
    });
  });

  describe('Complex Scenarios', () => {
    it('should render dialog for destructive clean operation', () => {
      const props: ConfirmDialogProps = {
        open: true,
        title: 'Confirm Cleanup',
        message: 'The following cleanup will be performed:',
        details: [
          'Items to remove: 150',
          'Space to recover: 2.5 GB',
          'Caches: 1.8 GB',
          'Logs: 700 MB',
        ],
        confirmLabel: 'Clean Now',
        cancelLabel: 'Cancel',
        onConfirm: mockOnConfirm,
        onCancel: mockOnCancel,
        destructive: true,
      };

      render(<ConfirmDialog {...props} />);

      expect(screen.getByText('Confirm Cleanup')).toBeInTheDocument();
      expect(screen.getByText('The following cleanup will be performed:')).toBeInTheDocument();
      expect(screen.getByText('Items to remove: 150')).toBeInTheDocument();
      expect(screen.getByText('Space to recover: 2.5 GB')).toBeInTheDocument();
      expect(screen.getByText('Clean Now')).toBeInTheDocument();

      const confirmButton = screen.getByText('Clean Now');
      expect(confirmButton).toHaveClass('destructive');
    });

    it('should render dialog for agent command confirmation', () => {
      const props: ConfirmDialogProps = {
        open: true,
        title: 'Confirm Destructive Command',
        message: 'Review the dry-run preview before proceeding:',
        details: [
          'Command: mo clean',
          'Dry-run preview completed.',
          'Destructive command requires dry-run preview and confirmation',
          '',
          'Preview results:',
          'Would remove 150 items totaling 2.5 GB',
        ],
        confirmLabel: 'Proceed',
        cancelLabel: 'Cancel',
        onConfirm: mockOnConfirm,
        onCancel: mockOnCancel,
        destructive: false,
      };

      render(<ConfirmDialog {...props} />);

      expect(screen.getByText('Confirm Destructive Command')).toBeInTheDocument();
      expect(screen.getByText('Command: mo clean')).toBeInTheDocument();
      expect(screen.getByText('Dry-run preview completed.')).toBeInTheDocument();
      expect(screen.getByText('Proceed')).toBeInTheDocument();
    });

    it('should handle rapid open/close cycles', () => {
      const { rerender } = render(<ConfirmDialog {...defaultProps} open={false} />);

      expect(screen.queryByText('Test Title')).not.toBeInTheDocument();

      rerender(<ConfirmDialog {...defaultProps} open={true} />);
      expect(screen.getByText('Test Title')).toBeInTheDocument();

      rerender(<ConfirmDialog {...defaultProps} open={false} />);
      expect(screen.queryByText('Test Title')).not.toBeInTheDocument();

      rerender(<ConfirmDialog {...defaultProps} open={true} />);
      expect(screen.getByText('Test Title')).toBeInTheDocument();
    });

    it('should update content when props change while open', () => {
      const { rerender } = render(
        <ConfirmDialog
          {...defaultProps}
          title="Original Title"
          message="Original Message"
        />
      );

      expect(screen.getByText('Original Title')).toBeInTheDocument();
      expect(screen.getByText('Original Message')).toBeInTheDocument();

      rerender(
        <ConfirmDialog
          {...defaultProps}
          title="Updated Title"
          message="Updated Message"
        />
      );

      expect(screen.getByText('Updated Title')).toBeInTheDocument();
      expect(screen.getByText('Updated Message')).toBeInTheDocument();
      expect(screen.queryByText('Original Title')).not.toBeInTheDocument();
      expect(screen.queryByText('Original Message')).not.toBeInTheDocument();
    });
  });

  describe('Accessibility', () => {
    it('should have proper button roles', () => {
      render(<ConfirmDialog {...defaultProps} />);

      const buttons = screen.getAllByRole('button');
      expect(buttons).toHaveLength(2);
    });

    it('should have appropriate class names for styling', () => {
      render(<ConfirmDialog {...defaultProps} />);

      const confirmButton = screen.getByText('Confirm');
      expect(confirmButton).toHaveClass('dialog-button');
      expect(confirmButton).toHaveClass('confirm-button');

      const cancelButton = screen.getByText('Cancel');
      expect(cancelButton).toHaveClass('dialog-button');
      expect(cancelButton).toHaveClass('cancel-button');
    });

    it('should render title as h3 heading', () => {
      render(<ConfirmDialog {...defaultProps} />);

      const heading = screen.getByRole('heading', { level: 3 });
      expect(heading).toHaveTextContent('Test Title');
    });
  });
});
