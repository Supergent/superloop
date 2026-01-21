import { useEffect, useRef } from 'react';
import { animate } from 'animejs';
import { type GateStatus, type GatesState, GATE_NAMES } from '../types';

interface GatePillsProps {
  gates: GatesState;
}

const GATE_LABELS: Record<keyof GatesState, string> = {
  promise: 'Promise',
  tests: 'Tests',
  checklist: 'Checklist',
  evidence: 'Evidence',
  approval: 'Approval',
};

const STATUS_STYLES: Record<GateStatus, { bg: string; text: string; icon: string }> = {
  passed: {
    bg: 'bg-loop-success/20',
    text: 'text-loop-success',
    icon: '\u2713',
  },
  failed: {
    bg: 'bg-loop-error/20',
    text: 'text-loop-error',
    icon: '\u2717',
  },
  pending: {
    bg: 'bg-loop-border',
    text: 'text-loop-muted',
    icon: '\u2022',
  },
  skipped: {
    bg: 'bg-loop-border/50',
    text: 'text-loop-muted/50',
    icon: '-',
  },
};

interface GatePillProps {
  name: keyof GatesState;
  status: GateStatus;
  index: number;
}

function GatePill({ name, status, index }: GatePillProps) {
  const pillRef = useRef<HTMLDivElement>(null);
  const prevStatusRef = useRef<GateStatus>(status);

  useEffect(() => {
    if (!pillRef.current) return;

    if (prevStatusRef.current !== status) {
      // Animate scale on status change
      animate(pillRef.current, {
        scale: [1, 1.1, 1],
        duration: 400,
        ease: 'outElastic(1, 0.5)',
        delay: index * 50,
      });
    }

    prevStatusRef.current = status;
  }, [status, index]);

  const styles = STATUS_STYLES[status];

  return (
    <div
      ref={pillRef}
      className={`
        gate-pill flex items-center gap-2 px-3 py-2 rounded-lg
        ${styles.bg} ${styles.text}
        transition-colors duration-300
      `}
    >
      <span className="text-sm font-mono">{styles.icon}</span>
      <span className="text-sm font-medium">{GATE_LABELS[name]}</span>
    </div>
  );
}

/**
 * GatePills - Horizontal gate status row
 *
 * Shows all 5 gates with their current status.
 * Pills expand/contract with scale animation on status change.
 */
export function GatePills({ gates }: GatePillsProps) {
  return (
    <div className="flex flex-wrap gap-2 justify-center">
      {GATE_NAMES.map((name, index) => (
        <GatePill key={name} name={name} status={gates[name]} index={index} />
      ))}
    </div>
  );
}
