import { useEffect, useRef } from 'react';
import { animate } from 'animejs';
import { type LoopPhase, PHASES } from '../types';

interface PhaseRingProps {
  phase: LoopPhase | null;
  active: boolean;
}

const PHASE_LABELS: Record<LoopPhase, string> = {
  planner: 'Plan',
  implementer: 'Impl',
  tester: 'Test',
  reviewer: 'Review',
};

const PHASE_COLORS: Record<LoopPhase, string> = {
  planner: '#8b5cf6', // purple
  implementer: '#3b82f6', // blue
  tester: '#22c55e', // green
  reviewer: '#f59e0b', // amber
};

/**
 * PhaseRing - Circular 4-phase indicator
 *
 * Shows the current phase in the superloop cycle.
 * Rotates smoothly on phase change with Anime.js.
 */
export function PhaseRing({ phase, active }: PhaseRingProps) {
  const ringRef = useRef<SVGGElement>(null);
  const prevPhaseRef = useRef<LoopPhase | null>(null);

  useEffect(() => {
    if (!ringRef.current || !active) return;

    const prevIndex = prevPhaseRef.current ? PHASES.indexOf(prevPhaseRef.current) : -1;
    const currentIndex = phase ? PHASES.indexOf(phase) : -1;

    if (prevIndex !== currentIndex && currentIndex >= 0) {
      // Calculate shortest rotation path
      let fromRotation = prevIndex >= 0 ? prevIndex * 90 : 0;
      let toRotation = currentIndex * 90;

      // Handle wrap-around (reviewer -> planner)
      if (prevIndex === 3 && currentIndex === 0) {
        toRotation = 360;
      }

      animate(ringRef.current, {
        rotate: [fromRotation, toRotation],
        duration: 600,
        ease: 'outExpo',
        complete: () => {
          // Reset to 0 if we went to 360
          if (toRotation === 360 && ringRef.current) {
            ringRef.current.style.transform = 'rotate(0deg)';
          }
        },
      });
    }

    prevPhaseRef.current = phase;
  }, [phase, active]);

  return (
    <div className="relative w-48 h-48">
      <svg viewBox="0 0 100 100" className="w-full h-full">
        {/* Background ring */}
        <circle
          cx="50"
          cy="50"
          r="40"
          fill="none"
          stroke="#1e1e2e"
          strokeWidth="8"
          className="opacity-50"
        />

        {/* Phase segments */}
        <g ref={ringRef} style={{ transformOrigin: '50px 50px' }}>
          {PHASES.map((p, i) => {
            const isActive = p === phase && active;
            const angle = i * 90;
            const startAngle = (angle - 45) * (Math.PI / 180);
            const endAngle = (angle + 45) * (Math.PI / 180);

            const x1 = 50 + 40 * Math.cos(startAngle);
            const y1 = 50 + 40 * Math.sin(startAngle);
            const x2 = 50 + 40 * Math.cos(endAngle);
            const y2 = 50 + 40 * Math.sin(endAngle);

            return (
              <path
                key={p}
                d={`M ${x1} ${y1} A 40 40 0 0 1 ${x2} ${y2}`}
                fill="none"
                stroke={isActive ? PHASE_COLORS[p] : '#2d2d3d'}
                strokeWidth="8"
                strokeLinecap="round"
                className="transition-colors duration-300"
              />
            );
          })}
        </g>

        {/* Phase indicator (points to current phase at top) */}
        <circle
          cx="50"
          cy="10"
          r="4"
          fill={active && phase ? PHASE_COLORS[phase] : '#6b7280'}
          className="transition-colors duration-300"
        />

        {/* Center text */}
        <text
          x="50"
          y="50"
          textAnchor="middle"
          dominantBaseline="middle"
          className="fill-loop-text text-xs font-medium"
          style={{ fontSize: '10px' }}
        >
          {active && phase ? PHASE_LABELS[phase] : 'Idle'}
        </text>
      </svg>

      {/* Phase labels around the ring */}
      <div className="absolute inset-0 pointer-events-none">
        {PHASES.map((p, i) => {
          const angle = (i * 90 - 90) * (Math.PI / 180);
          const x = 50 + 60 * Math.cos(angle);
          const y = 50 + 60 * Math.sin(angle);

          return (
            <span
              key={p}
              className={`absolute text-xs transform -translate-x-1/2 -translate-y-1/2 transition-colors duration-300 ${
                p === phase && active ? 'text-white font-medium' : 'text-loop-muted'
              }`}
              style={{
                left: `${x}%`,
                top: `${y}%`,
              }}
            >
              {PHASE_LABELS[p]}
            </span>
          );
        })}
      </div>
    </div>
  );
}
