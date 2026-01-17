import React from 'react';

export interface ConversationTurn {
  id: string;
  timestamp: number;
  role: 'user' | 'assistant';
  text: string;
  intent?: string;
}

export interface VoiceConversationProps {
  turns: ConversationTurn[];
  maxTurns?: number;
  showTimestamps?: boolean;
}

export function VoiceConversation({
  turns,
  maxTurns = 6,
  showTimestamps = false,
}: VoiceConversationProps) {
  // Show most recent turns (reverse chronological)
  const displayTurns = turns.slice(-maxTurns);

  if (displayTurns.length === 0) {
    return (
      <div className="voice-conversation empty">
        <p className="empty-message">No conversation yet. Try "How's my Mac?"</p>
      </div>
    );
  }

  const formatTimestamp = (timestamp: number): string => {
    const date = new Date(timestamp);
    const hours = date.getHours().toString().padStart(2, '0');
    const minutes = date.getMinutes().toString().padStart(2, '0');
    return `${hours}:${minutes}`;
  };

  return (
    <div className="voice-conversation">
      {displayTurns.map((turn) => (
        <div
          key={turn.id}
          className={`conversation-turn ${turn.role}`}
        >
          <div className="turn-content">
            <div className="turn-role">
              {turn.role === 'user' ? '🎤' : '🤖'}
              <span className="role-label">
                {turn.role === 'user' ? 'You' : 'Valet'}
              </span>
              {turn.intent && (
                <span className="intent-badge">{turn.intent}</span>
              )}
            </div>
            <div className="turn-text">{turn.text}</div>
            {showTimestamps && (
              <div className="turn-timestamp">
                {formatTimestamp(turn.timestamp)}
              </div>
            )}
          </div>
        </div>
      ))}
    </div>
  );
}
