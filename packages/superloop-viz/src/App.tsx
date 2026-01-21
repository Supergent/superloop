import { useEffect, useState } from 'react';
import { MockProvider, useMockState } from './data/mock-provider';
import { LiveProvider, useLiveState } from './data/live-provider';
import { PhaseRing } from './components/PhaseRing';
import { GatePills } from './components/GatePills';
import { IterationCounter } from './components/IterationCounter';
import { LoopStateBadge } from './components/LoopStateBadge';
import { type LoopState } from './types';

type DataMode = 'mock' | 'live';

function MockVisualization({ onModeChange }: { onModeChange: (mode: DataMode) => void }) {
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
        case 'l':
        case 'L':
          onModeChange('live');
          break;
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [nextState, prevState, autoPlay, setAutoPlay, showStuck, setShowStuck, onModeChange]);

  return (
    <VisualizationLayout
      state={state}
      mode="mock"
      onModeChange={onModeChange}
      footer={
        <MockControls
          stateIndex={stateIndex}
          totalStates={totalStates}
          autoPlay={autoPlay}
          showStuck={showStuck}
          onNext={nextState}
          onPrev={prevState}
          onToggleAutoPlay={() => setAutoPlay(!autoPlay)}
          onToggleStuck={() => setShowStuck(!showStuck)}
        />
      }
    />
  );
}

function LiveVisualization({ onModeChange }: { onModeChange: (mode: DataMode) => void }) {
  const {
    state,
    availableLoops,
    selectedLoop,
    selectLoop,
    isLoading,
    error,
    refresh,
    pollInterval,
    setPollInterval,
  } = useLiveState();

  // Keyboard controls
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      switch (e.key) {
        case 'r':
        case 'R':
          refresh();
          break;
        case 'm':
        case 'M':
          onModeChange('mock');
          break;
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [refresh, onModeChange]);

  return (
    <VisualizationLayout
      state={state}
      mode="live"
      onModeChange={onModeChange}
      isLoading={isLoading}
      error={error}
      footer={
        <LiveControls
          availableLoops={availableLoops}
          selectedLoop={selectedLoop}
          pollInterval={pollInterval}
          onSelectLoop={selectLoop}
          onRefresh={refresh}
          onSetPollInterval={setPollInterval}
        />
      }
    />
  );
}

interface VisualizationLayoutProps {
  state: LoopState;
  mode: DataMode;
  onModeChange: (mode: DataMode) => void;
  footer: React.ReactNode;
  isLoading?: boolean;
  error?: string | null;
}

function VisualizationLayout({
  state,
  mode,
  onModeChange,
  footer,
  isLoading,
  error,
}: VisualizationLayoutProps) {
  const isActive = state.status !== 'idle';

  return (
    <div className="min-h-screen bg-loop-bg flex flex-col">
      {/* Header */}
      <header className="p-6 border-b border-loop-border">
        <div className="max-w-4xl mx-auto flex items-center justify-between">
          <div className="flex items-center gap-4">
            <h1 className="text-xl font-semibold text-loop-text">
              Superloop Visualization
            </h1>
            {/* Mode toggle */}
            <div className="flex rounded-lg overflow-hidden border border-loop-border">
              <button
                onClick={() => onModeChange('mock')}
                className={`px-3 py-1 text-sm transition-colors ${
                  mode === 'mock'
                    ? 'bg-loop-accent text-white'
                    : 'bg-loop-surface text-loop-muted hover:text-loop-text'
                }`}
              >
                Demo
              </button>
              <button
                onClick={() => onModeChange('live')}
                className={`px-3 py-1 text-sm transition-colors ${
                  mode === 'live'
                    ? 'bg-loop-accent text-white'
                    : 'bg-loop-surface text-loop-muted hover:text-loop-text'
                }`}
              >
                Live
              </button>
            </div>
          </div>
          <div className="flex items-center gap-4">
            {isLoading && (
              <span className="text-xs text-loop-muted animate-pulse">Loading...</span>
            )}
            {error && <span className="text-xs text-loop-error">{error}</span>}
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

          {/* Loop ID */}
          {state.loopId && (
            <div className="text-center">
              <span className="text-sm text-loop-muted">
                Loop: <span className="text-loop-text font-mono">{state.loopId}</span>
              </span>
            </div>
          )}

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
      <footer className="p-6 border-t border-loop-border">{footer}</footer>
    </div>
  );
}

interface MockControlsProps {
  stateIndex: number;
  totalStates: number;
  autoPlay: boolean;
  showStuck: boolean;
  onNext: () => void;
  onPrev: () => void;
  onToggleAutoPlay: () => void;
  onToggleStuck: () => void;
}

function MockControls({
  stateIndex,
  totalStates,
  autoPlay,
  showStuck,
  onNext,
  onPrev,
  onToggleAutoPlay,
  onToggleStuck,
}: MockControlsProps) {
  return (
    <div className="max-w-4xl mx-auto">
      {/* Progress bar */}
      <div className="mb-4">
        <div className="flex items-center justify-between text-xs text-loop-muted mb-2">
          <span>
            State {stateIndex + 1} of {totalStates}
          </span>
          <span>Demo Mode</span>
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
          onClick={onPrev}
          className="px-4 py-2 rounded-lg bg-loop-surface border border-loop-border text-loop-text hover:bg-loop-border transition-colors"
        >
          Previous
        </button>

        <button
          onClick={onToggleAutoPlay}
          className={`px-4 py-2 rounded-lg border transition-colors ${
            autoPlay
              ? 'bg-loop-accent/20 border-loop-accent text-loop-accent'
              : 'bg-loop-surface border-loop-border text-loop-text hover:bg-loop-border'
          }`}
        >
          {autoPlay ? 'Pause' : 'Auto-play'}
        </button>

        <button
          onClick={onNext}
          className="px-4 py-2 rounded-lg bg-loop-surface border border-loop-border text-loop-text hover:bg-loop-border transition-colors"
        >
          Next
        </button>

        <button
          onClick={onToggleStuck}
          className={`px-4 py-2 rounded-lg border transition-colors ${
            showStuck
              ? 'bg-loop-warning/20 border-loop-warning text-loop-warning'
              : 'bg-loop-surface border-loop-border text-loop-text hover:bg-loop-border'
          }`}
        >
          Stuck Demo
        </button>
      </div>

      {/* Keyboard hints */}
      <div className="mt-4 text-center text-xs text-loop-muted">
        <span className="inline-flex items-center gap-4 flex-wrap justify-center">
          <span>
            <kbd className="px-1.5 py-0.5 rounded bg-loop-surface border border-loop-border">
              Space
            </kbd>{' '}
            Next
          </span>
          <span>
            <kbd className="px-1.5 py-0.5 rounded bg-loop-surface border border-loop-border">
              A
            </kbd>{' '}
            Auto-play
          </span>
          <span>
            <kbd className="px-1.5 py-0.5 rounded bg-loop-surface border border-loop-border">
              S
            </kbd>{' '}
            Stuck
          </span>
          <span>
            <kbd className="px-1.5 py-0.5 rounded bg-loop-surface border border-loop-border">
              L
            </kbd>{' '}
            Live mode
          </span>
        </span>
      </div>
    </div>
  );
}

interface LiveControlsProps {
  availableLoops: string[];
  selectedLoop: string | null;
  pollInterval: number;
  onSelectLoop: (loopId: string) => void;
  onRefresh: () => void;
  onSetPollInterval: (ms: number) => void;
}

function LiveControls({
  availableLoops,
  selectedLoop,
  pollInterval,
  onSelectLoop,
  onRefresh,
  onSetPollInterval,
}: LiveControlsProps) {
  return (
    <div className="max-w-4xl mx-auto">
      {/* Loop selector and controls */}
      <div className="flex items-center justify-center gap-4 mb-4">
        {availableLoops.length > 0 && (
          <select
            value={selectedLoop ?? ''}
            onChange={(e) => onSelectLoop(e.target.value)}
            className="px-3 py-2 rounded-lg bg-loop-surface border border-loop-border text-loop-text"
          >
            {availableLoops.map((loop) => (
              <option key={loop} value={loop}>
                {loop}
              </option>
            ))}
          </select>
        )}

        <button
          onClick={onRefresh}
          className="px-4 py-2 rounded-lg bg-loop-surface border border-loop-border text-loop-text hover:bg-loop-border transition-colors"
        >
          Refresh
        </button>

        <select
          value={pollInterval}
          onChange={(e) => onSetPollInterval(Number(e.target.value))}
          className="px-3 py-2 rounded-lg bg-loop-surface border border-loop-border text-loop-text"
        >
          <option value={0}>Polling: Off</option>
          <option value={1000}>Poll: 1s</option>
          <option value={2000}>Poll: 2s</option>
          <option value={5000}>Poll: 5s</option>
          <option value={10000}>Poll: 10s</option>
        </select>
      </div>

      {/* Keyboard hints */}
      <div className="text-center text-xs text-loop-muted">
        <span className="inline-flex items-center gap-4">
          <span>
            <kbd className="px-1.5 py-0.5 rounded bg-loop-surface border border-loop-border">
              R
            </kbd>{' '}
            Refresh
          </span>
          <span>
            <kbd className="px-1.5 py-0.5 rounded bg-loop-surface border border-loop-border">
              M
            </kbd>{' '}
            Demo mode
          </span>
        </span>
      </div>
    </div>
  );
}

export default function App() {
  const [mode, setMode] = useState<DataMode>('mock');

  if (mode === 'mock') {
    return (
      <MockProvider>
        <MockVisualization onModeChange={setMode} />
      </MockProvider>
    );
  }

  return (
    <LiveProvider>
      <LiveVisualization onModeChange={setMode} />
    </LiveProvider>
  );
}
