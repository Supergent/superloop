import { useEffect, useRef } from 'react';
import { animate } from 'animejs';

interface IterationCounterProps {
  iteration: number;
  active: boolean;
}

/**
 * IterationCounter - Number flip with scale effect
 *
 * Displays the current iteration number with a smooth
 * flip/scale animation when the number changes.
 */
export function IterationCounter({ iteration, active }: IterationCounterProps) {
  const numberRef = useRef<HTMLSpanElement>(null);
  const prevIterationRef = useRef(iteration);

  useEffect(() => {
    if (!numberRef.current) return;

    if (prevIterationRef.current !== iteration && iteration > 0) {
      // Flip animation on iteration change
      animate(numberRef.current, {
        scale: [1, 1.3, 1],
        rotateX: [0, 360],
        duration: 600,
        ease: 'outExpo',
      });
    }

    prevIterationRef.current = iteration;
  }, [iteration]);

  return (
    <div className="flex flex-col items-center gap-2">
      <span className="text-xs uppercase tracking-wider text-loop-muted">
        Iteration
      </span>
      <div
        className={`
          relative w-20 h-20 rounded-xl
          flex items-center justify-center
          ${active ? 'bg-loop-accent/20' : 'bg-loop-border'}
          transition-colors duration-300
        `}
      >
        <span
          ref={numberRef}
          className={`
            text-4xl font-bold font-mono
            ${active ? 'text-loop-accent' : 'text-loop-muted'}
            transition-colors duration-300
          `}
          style={{ perspective: '100px' }}
        >
          {iteration}
        </span>

        {/* Glow effect when active */}
        {active && (
          <div className="absolute inset-0 rounded-xl bg-loop-accent/10 animate-pulse-slow" />
        )}
      </div>
    </div>
  );
}
