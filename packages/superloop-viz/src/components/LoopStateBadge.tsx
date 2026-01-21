import { useEffect, useRef } from 'react';
import { animate } from 'animejs';
import { type LoopStatus } from '../types';

interface LoopStateBadgeProps {
  status: LoopStatus;
  stuckCount?: number;
}

const STATUS_CONFIG: Record<
  LoopStatus,
  { label: string; bg: string; text: string; glow: string }
> = {
  idle: {
    label: 'Idle',
    bg: 'bg-loop-border',
    text: 'text-loop-muted',
    glow: '',
  },
  in_progress: {
    label: 'Running',
    bg: 'bg-loop-info/20',
    text: 'text-loop-info',
    glow: 'shadow-loop-info/30',
  },
  stuck: {
    label: 'Stuck',
    bg: 'bg-loop-warning/20',
    text: 'text-loop-warning',
    glow: 'shadow-loop-warning/30',
  },
  awaiting_approval: {
    label: 'Awaiting Approval',
    bg: 'bg-loop-accent/20',
    text: 'text-loop-accent',
    glow: 'shadow-loop-accent/30',
  },
  complete: {
    label: 'Complete',
    bg: 'bg-loop-success/20',
    text: 'text-loop-success',
    glow: 'shadow-loop-success/30',
  },
};

/**
 * LoopStateBadge - State color morphing badge
 *
 * Shows the current loop status with smooth color transitions.
 * Animates with scale/morph effect on status change.
 */
export function LoopStateBadge({ status, stuckCount = 0 }: LoopStateBadgeProps) {
  const badgeRef = useRef<HTMLDivElement>(null);
  const prevStatusRef = useRef(status);

  useEffect(() => {
    if (!badgeRef.current) return;

    if (prevStatusRef.current !== status) {
      // Morph animation on status change
      animate(badgeRef.current, {
        scale: [1, 1.05, 1],
        duration: 400,
        ease: 'outExpo',
      });
    }

    prevStatusRef.current = status;
  }, [status]);

  const config = STATUS_CONFIG[status];

  return (
    <div
      ref={badgeRef}
      className={`
        inline-flex items-center gap-2 px-4 py-2 rounded-full
        ${config.bg} ${config.text}
        ${config.glow ? `shadow-lg ${config.glow}` : ''}
        transition-all duration-500
      `}
    >
      {/* Status indicator dot */}
      <span
        className={`
          w-2 h-2 rounded-full
          ${status === 'in_progress' ? 'animate-pulse' : ''}
          ${status === 'idle' ? 'bg-loop-muted' : ''}
          ${status === 'in_progress' ? 'bg-loop-info' : ''}
          ${status === 'stuck' ? 'bg-loop-warning' : ''}
          ${status === 'awaiting_approval' ? 'bg-loop-accent' : ''}
          ${status === 'complete' ? 'bg-loop-success' : ''}
        `}
      />

      {/* Label */}
      <span className="text-sm font-medium">{config.label}</span>

      {/* Stuck count badge */}
      {status === 'stuck' && stuckCount > 0 && (
        <span className="ml-1 px-2 py-0.5 text-xs bg-loop-warning/30 rounded-full">
          x{stuckCount}
        </span>
      )}
    </div>
  );
}
