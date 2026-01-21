import { useEffect } from 'react';
import { MockProvider, useMockState } from './data/mock-provider';
import { PhaseRing } from './components/PhaseRing';
import { GatePills } from './components/GatePills';
import { IterationCounter } from './components/IterationCounter';
import { LoopStateBadge } from './components/LoopStateBadge';

function Visualization() {
  const {
    state,
    stateIndex,
    totalStates,
    nextState,
    prevState,
    autoPlay,
    setAutoPlay,
    showStuck,
    setShowStuck,
  } = useMockState();

  // Keyboard controls
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      switch (e.key) {
        case ' ':
        case 'ArrowRight':
          e.preventDefault();
          nextState();
          break;
        case 'ArrowLeft':
          e.preventDefault();
          prevState();
          break;
        case 'a':
        case 'A':
          setAutoPlay(!autoPlay);
          break;
        case 's':
        case 'S':
          setShowStuck(!showStuck);
          break;
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [nextState, prevState, autoPlay, setAutoPlay, showStuck, setShowStuck]);

  const isActive = state.status !== 'idle';

  return (
    <div className="min-h-screen bg-loop-bg flex flex-col">
      {/* Header */}
      <header className="p-6 border-b border-loop-border">
        <div className="max-w-4xl mx-auto flex items-center justify-between">
          <h1 className="text-xl font-semibold text-loop-text">
            Superloop Visualization
          </h1>
          <div className="flex items-center gap-4">
            <LoopStateBadge status={state.status} stuckCount={state.stuckCount} />
          </div>
        </div>
      </header>

      {/* Main visualization area */}
      <main className="flex-1 flex items-center justify-center p-8">
        <div className="max-w-4xl w-full space-y-12">
          {/* Top row: Phase ring and iteration counter */}
          <div className="flex items-center justify-center gap-16">
            <PhaseRing phase={state.phase} active={isActive} />
            <IterationCounter iteration={state.iteration} active={isActive} />
          </div>

          {/* Gates */}
          <div className="py-4">
            <GatePills gates={state.gates} />
          </div>

          {/* Stuck reason (if applicable) */}
          {state.stuckReason && (
            <div className="text-center">
              <p className="text-sm text-loop-warning bg-loop-warning/10 px-4 py-2 rounded-lg inline-block">
                {state.stuckReason}
              </p>
            </div>
          )}
        </div>
      </main>

      {/* Controls */}
      <footer className="p-6 border-t border-loop-border">
        <div className="max-w-4xl mx-auto">
          {/* Progress bar */}
          <div className="mb-4">
            <div className="flex items-center justify-between text-xs text-loop-muted mb-2">
              <span>State {stateIndex + 1} of {totalStates}</span>
              <span>{state.loopId ?? 'No loop'}</span>
            </div>
            <div className="h-1 bg-loop-border rounded-full overflow-hidden">
              <div
                className="h-full bg-loop-accent transition-all duration-300"
                style={{ width: `${((stateIndex + 1) / totalStates) * 100}%` }}
              />
            </div>
          </div>

          {/* Control buttons */}
          <div className="flex items-center justify-center gap-4">
            <button
              onClick={prevState}
              className="px-4 py-2 rounded-lg bg-loop-surface border border-loop-border text-loop-text hover:bg-loop-border transition-colors"
            >
              Previous
            </button>

            <button
              onClick={() => setAutoPlay(!autoPlay)}
              className={`px-4 py-2 rounded-lg border transition-colors ${
                autoPlay
                  ? 'bg-loop-accent/20 border-loop-accent text-loop-accent'
                  : 'bg-loop-surface border-loop-border text-loop-text hover:bg-loop-border'
              }`}
            >
              {autoPlay ? 'Pause' : 'Auto-play'}
            </button>

            <button
              onClick={nextState}
              className="px-4 py-2 rounded-lg bg-loop-surface border border-loop-border text-loop-text hover:bg-loop-border transition-colors"
            >
              Next
            </button>
          </div>

          {/* Keyboard hints */}
          <div className="mt-4 text-center text-xs text-loop-muted">
            <span className="inline-flex items-center gap-4">
              <span>
                <kbd className="px-1.5 py-0.5 rounded bg-loop-surface border border-loop-border">Space</kbd>
                {' '}or{' '}
                <kbd className="px-1.5 py-0.5 rounded bg-loop-surface border border-loop-border">\u2192</kbd>
                {' '}Next
              </span>
              <span>
                <kbd className="px-1.5 py-0.5 rounded bg-loop-surface border border-loop-border">\u2190</kbd>
                {' '}Previous
              </span>
              <span>
                <kbd className="px-1.5 py-0.5 rounded bg-loop-surface border border-loop-border">A</kbd>
                {' '}Auto-play
              </span>
              <span>
                <kbd className="px-1.5 py-0.5 rounded bg-loop-surface border border-loop-border">S</kbd>
                {' '}Stuck mode: {showStuck ? 'ON' : 'OFF'}
              </span>
            </span>
          </div>
        </div>
      </footer>
    </div>
  );
}

export default function App() {
  return (
    <MockProvider>
      <Visualization />
    </MockProvider>
  );
}
