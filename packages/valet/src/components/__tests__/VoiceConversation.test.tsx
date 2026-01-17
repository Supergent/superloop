import { describe, it, expect, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import { VoiceConversation, type ConversationTurn } from '../VoiceConversation';

describe('VoiceConversation', () => {
  const mockTurns: ConversationTurn[] = [
    {
      id: 'turn-1',
      timestamp: new Date('2024-01-01T10:30:00').getTime(),
      role: 'user',
      text: 'How is my Mac doing?',
      intent: 'status',
    },
    {
      id: 'turn-2',
      timestamp: new Date('2024-01-01T10:30:05').getTime(),
      role: 'assistant',
      text: 'Your Mac is in good health with 50% disk usage.',
    },
    {
      id: 'turn-3',
      timestamp: new Date('2024-01-01T10:31:00').getTime(),
      role: 'user',
      text: 'Clean my Mac',
      intent: 'clean',
    },
    {
      id: 'turn-4',
      timestamp: new Date('2024-01-01T10:31:05').getTime(),
      role: 'assistant',
      text: 'I can help you clean your Mac. This will remove temporary files and caches.',
    },
  ];

  describe('Rendering', () => {
    it('should render conversation turns', () => {
      render(<VoiceConversation turns={mockTurns} />);

      expect(screen.getByText('How is my Mac doing?')).toBeInTheDocument();
      expect(screen.getByText('Your Mac is in good health with 50% disk usage.')).toBeInTheDocument();
      expect(screen.getByText('Clean my Mac')).toBeInTheDocument();
    });

    it('should show empty message when no turns', () => {
      render(<VoiceConversation turns={[]} />);

      expect(screen.getByText(/No conversation yet/)).toBeInTheDocument();
      expect(screen.getByText(/Try.*How.*s my Mac/)).toBeInTheDocument();
    });

    it('should display user role with microphone icon', () => {
      render(<VoiceConversation turns={[mockTurns[0]]} />);

      expect(screen.getByText('🎤')).toBeInTheDocument();
      expect(screen.getByText('You')).toBeInTheDocument();
    });

    it('should display assistant role with robot icon', () => {
      render(<VoiceConversation turns={[mockTurns[1]]} />);

      expect(screen.getByText('🤖')).toBeInTheDocument();
      expect(screen.getByText('Valet')).toBeInTheDocument();
    });

    it('should show intent badge when intent is provided', () => {
      render(<VoiceConversation turns={[mockTurns[0]]} />);

      expect(screen.getByText('status')).toBeInTheDocument();
      expect(screen.getByText('status')).toHaveClass('intent-badge');
    });

    it('should not show intent badge when intent is not provided', () => {
      render(<VoiceConversation turns={[mockTurns[1]]} />);

      // Assistant turn doesn't have intent
      const intentBadges = screen.queryAllByText(/status|clean|uninstall/);
      expect(intentBadges.length).toBe(0);
    });

    it('should apply correct CSS classes to turns', () => {
      render(<VoiceConversation turns={[mockTurns[0], mockTurns[1]]} />);

      const userTurn = screen.getByText('How is my Mac doing?').closest('.conversation-turn');
      expect(userTurn).toHaveClass('user');

      const assistantTurn = screen.getByText('Your Mac is in good health with 50% disk usage.').closest('.conversation-turn');
      expect(assistantTurn).toHaveClass('assistant');
    });
  });

  describe('maxTurns prop', () => {
    it('should limit displayed turns to maxTurns', () => {
      render(<VoiceConversation turns={mockTurns} maxTurns={2} />);

      // Should only show last 2 turns
      expect(screen.queryByText('How is my Mac doing?')).not.toBeInTheDocument();
      expect(screen.queryByText('Your Mac is in good health with 50% disk usage.')).not.toBeInTheDocument();
      expect(screen.getByText('Clean my Mac')).toBeInTheDocument();
      expect(screen.getByText('I can help you clean your Mac. This will remove temporary files and caches.')).toBeInTheDocument();
    });

    it('should show all turns when total is less than maxTurns', () => {
      render(<VoiceConversation turns={[mockTurns[0], mockTurns[1]]} maxTurns={5} />);

      expect(screen.getByText('How is my Mac doing?')).toBeInTheDocument();
      expect(screen.getByText('Your Mac is in good health with 50% disk usage.')).toBeInTheDocument();
    });

    it('should use default maxTurns of 6 when not specified', () => {
      const manyTurns: ConversationTurn[] = Array.from({ length: 10 }, (_, i) => ({
        id: `turn-${i}`,
        timestamp: Date.now() + i * 1000,
        role: i % 2 === 0 ? 'user' : 'assistant',
        text: `Message ${i}`,
      }));

      render(<VoiceConversation turns={manyTurns} />);

      // Should only show last 6 turns (turns 4-9)
      expect(screen.queryByText('Message 0')).not.toBeInTheDocument();
      expect(screen.queryByText('Message 1')).not.toBeInTheDocument();
      expect(screen.queryByText('Message 2')).not.toBeInTheDocument();
      expect(screen.queryByText('Message 3')).not.toBeInTheDocument();
      expect(screen.getByText('Message 4')).toBeInTheDocument();
      expect(screen.getByText('Message 9')).toBeInTheDocument();
    });

    it('should show most recent turns when maxTurns is exceeded', () => {
      const turns: ConversationTurn[] = [
        { id: '1', timestamp: 1000, role: 'user', text: 'Old message' },
        { id: '2', timestamp: 2000, role: 'assistant', text: 'Old response' },
        { id: '3', timestamp: 3000, role: 'user', text: 'Recent message' },
      ];

      render(<VoiceConversation turns={turns} maxTurns={2} />);

      expect(screen.queryByText('Old message')).not.toBeInTheDocument();
      expect(screen.getByText('Old response')).toBeInTheDocument();
      expect(screen.getByText('Recent message')).toBeInTheDocument();
    });
  });

  describe('showTimestamps prop', () => {
    it('should show timestamps when showTimestamps is true', () => {
      render(<VoiceConversation turns={[mockTurns[0]]} showTimestamps={true} />);

      // Timestamp should be formatted as HH:MM
      expect(screen.getByText('10:30')).toBeInTheDocument();
    });

    it('should not show timestamps when showTimestamps is false', () => {
      render(<VoiceConversation turns={[mockTurns[0]]} showTimestamps={false} />);

      expect(screen.queryByText('10:30')).not.toBeInTheDocument();
    });

    it('should not show timestamps by default', () => {
      render(<VoiceConversation turns={[mockTurns[0]]} />);

      expect(screen.queryByText('10:30')).not.toBeInTheDocument();
    });

    it('should format timestamps correctly with padding', () => {
      const turn: ConversationTurn = {
        id: 'turn-1',
        timestamp: new Date('2024-01-01T09:05:00').getTime(),
        role: 'user',
        text: 'Test',
      };

      render(<VoiceConversation turns={[turn]} showTimestamps={true} />);

      // Should pad single-digit hours and minutes
      expect(screen.getByText('09:05')).toBeInTheDocument();
    });
  });

  describe('Complex Scenarios', () => {
    it('should handle mixed conversation with multiple intents', () => {
      const conversation: ConversationTurn[] = [
        {
          id: 't1',
          timestamp: Date.now(),
          role: 'user',
          text: 'How is my Mac?',
          intent: 'status',
        },
        {
          id: 't2',
          timestamp: Date.now() + 1000,
          role: 'assistant',
          text: 'Your Mac is healthy.',
        },
        {
          id: 't3',
          timestamp: Date.now() + 2000,
          role: 'user',
          text: 'Clean my system',
          intent: 'clean',
        },
        {
          id: 't4',
          timestamp: Date.now() + 3000,
          role: 'assistant',
          text: 'Running cleanup...',
        },
        {
          id: 't5',
          timestamp: Date.now() + 4000,
          role: 'user',
          text: 'Remove Slack',
          intent: 'uninstall',
        },
      ];

      render(<VoiceConversation turns={conversation} />);

      expect(screen.getByText('status')).toBeInTheDocument();
      expect(screen.getByText('clean')).toBeInTheDocument();
      expect(screen.getByText('uninstall')).toBeInTheDocument();
      expect(screen.getByText('Your Mac is healthy.')).toBeInTheDocument();
      expect(screen.getByText('Running cleanup...')).toBeInTheDocument();
    });

    it('should update when new turns are added', () => {
      const { rerender } = render(<VoiceConversation turns={[mockTurns[0]]} />);

      expect(screen.getByText('How is my Mac doing?')).toBeInTheDocument();
      expect(screen.queryByText('Your Mac is in good health with 50% disk usage.')).not.toBeInTheDocument();

      rerender(<VoiceConversation turns={[mockTurns[0], mockTurns[1]]} />);

      expect(screen.getByText('How is my Mac doing?')).toBeInTheDocument();
      expect(screen.getByText('Your Mac is in good health with 50% disk usage.')).toBeInTheDocument();
    });

    it('should transition from empty to populated state', () => {
      const { rerender } = render(<VoiceConversation turns={[]} />);

      expect(screen.getByText(/No conversation yet/)).toBeInTheDocument();

      rerender(<VoiceConversation turns={[mockTurns[0]]} />);

      expect(screen.queryByText(/No conversation yet/)).not.toBeInTheDocument();
      expect(screen.getByText('How is my Mac doing?')).toBeInTheDocument();
    });

    it('should handle long text content without breaking layout', () => {
      const longTurn: ConversationTurn = {
        id: 'long',
        timestamp: Date.now(),
        role: 'assistant',
        text: 'This is a very long response that contains a lot of detailed information about the system status, including disk usage, memory usage, CPU usage, and various other metrics that might be important for the user to know about their Mac system health.',
      };

      render(<VoiceConversation turns={[longTurn]} />);

      const text = screen.getByText(/This is a very long response/);
      expect(text).toBeInTheDocument();
      expect(text).toHaveClass('turn-text');
    });

    it('should maintain turn order', () => {
      render(<VoiceConversation turns={mockTurns} />);

      const allTurns = screen.getAllByText(/How is my Mac doing|Your Mac is in good health|Clean my Mac|I can help you clean/);

      // Verify order is maintained
      expect(allTurns[0]).toHaveTextContent('How is my Mac doing?');
      expect(allTurns[1]).toHaveTextContent('Your Mac is in good health');
      expect(allTurns[2]).toHaveTextContent('Clean my Mac');
      expect(allTurns[3]).toHaveTextContent('I can help you clean');
    });
  });

  describe('Edge Cases', () => {
    it('should handle turn with empty text', () => {
      const turn: ConversationTurn = {
        id: 'empty',
        timestamp: Date.now(),
        role: 'user',
        text: '',
      };

      render(<VoiceConversation turns={[turn]} />);

      // Should still render the turn structure
      expect(screen.getByText('You')).toBeInTheDocument();
    });

    it('should handle turn with special characters in text', () => {
      const turn: ConversationTurn = {
        id: 'special',
        timestamp: Date.now(),
        role: 'user',
        text: '<script>alert("xss")</script> & "quotes" \'apostrophes\'',
      };

      render(<VoiceConversation turns={[turn]} />);

      // Text should be escaped and rendered safely
      const text = screen.getByText(/<script>alert\("xss"\)<\/script> & "quotes" 'apostrophes'/);
      expect(text).toBeInTheDocument();
    });

    it('should handle maxTurns of 0', () => {
      render(<VoiceConversation turns={mockTurns} maxTurns={0} />);

      // Should show empty state
      expect(screen.getByText(/No conversation yet/)).toBeInTheDocument();
    });

    it('should handle maxTurns of 1', () => {
      render(<VoiceConversation turns={mockTurns} maxTurns={1} />);

      // Should only show the last turn
      expect(screen.queryByText('How is my Mac doing?')).not.toBeInTheDocument();
      expect(screen.getByText('I can help you clean your Mac. This will remove temporary files and caches.')).toBeInTheDocument();
    });
  });
});
