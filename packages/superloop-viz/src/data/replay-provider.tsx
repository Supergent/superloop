import {
  createContext,
  useContext,
  useState,
  useEffect,
  useCallback,
  type ReactNode,
} from 'react';
import { type LoopState, type GatesState, type LoopPhase, emptyState } from '../types';
import { fetchLoopList, fetchRunSummary } from './loader';

/** Raw iteration entry from run-summary.json */
interface RawIterationEntry {
  run_id: string;
  iteration: number;
  started_at: string;
  ended_at?: string;
  promise: {
    expected: string;
    text: string | null;
    matched: boolean;
  };
  gates: {
    tests: 'ok' | 'failed' | 'skipped';
    validation: 'ok' | 'failed' | 'skipped';
    checklist: 'ok' | 'failed' | 'skipped';
    evidence: 'ok' | 'failed' | 'skipped';
    approval: 'ok' | 'failed' | 'skipped';
  };
  stuck: {
    streak: number;
    threshold: number;
  };
  completion_ok: boolean;
  artifacts: Record<string, { path: string; exists: boolean }>;
}

function mapGateStatus(status: 'ok' | 'failed' | 'skipped'): GatesState[keyof GatesState] {
  switch (status) {
    case 'ok':
      return 'passed';
    case 'failed':
      return 'failed';
    case 'skipped':
      return 'skipped';
    default:
      return 'pending';
  }
}

/**
 * Infer phase based on the iteration outcome, not just artifact existence.
 *
 * Each iteration goes through all phases (planner → implementer → tester → reviewer),
 * so we infer based on where the iteration "ended" or what the key outcome was:
 *
 * - Tests failed → ended at tester phase
 * - Tests passed, promise not matched → reviewer phase (needs another iteration)
 * - Tests passed, promise matched → completed through reviewer
 * - First iteration → starts at planner
 */
function inferPhase(entry: RawIterationEntry): LoopPhase {
  const { gates, promise, completion_ok, iteration } = entry;

  // If tests failed, the significant phase was testing
  if (gates.tests === 'failed') {
    return 'tester';
  }

  // If tests passed but promise didn't match, went through review but incomplete
  if (gates.tests === 'ok' && !promise.matched) {
    return 'reviewer';
  }

  // If completed successfully, finished at reviewer
  if (completion_ok || promise.matched) {
    return 'reviewer';
  }

  // First iteration typically starts heavy in planning/implementation
  if (iteration === 1) {
    return 'implementer';
  }

  // Default: in implementation trying to fix issues
  return 'implementer';
}

function entryToState(entry: RawIterationEntry, loopId: string): LoopState {
  const isStuck = entry.stuck.streak >= entry.stuck.threshold;
  const isComplete = entry.completion_ok;
  const isAwaitingApproval =
    entry.promise.matched &&
    entry.gates.tests === 'ok' &&
    entry.gates.checklist === 'ok' &&
    entry.gates.approval === 'skipped';

  let status: LoopState['status'] = 'in_progress';
  if (isComplete) status = 'complete';
  else if (isStuck) status = 'stuck';
  else if (isAwaitingApproval) status = 'awaiting_approval';

  return {
    status,
    loopId,
    iteration: entry.iteration,
    phase: inferPhase(entry),
    gates: {
      promise: entry.promise.matched ? 'passed' : 'pending',
      tests: mapGateStatus(entry.gates.tests),
      checklist: mapGateStatus(entry.gates.checklist),
      evidence: mapGateStatus(entry.gates.evidence),
      approval: mapGateStatus(entry.gates.approval),
    },
    stuckCount: entry.stuck.streak,
    stuckReason:
      entry.stuck.streak > 0 ? `Stuck streak: ${entry.stuck.streak}/${entry.stuck.threshold}` : null,
    updatedAt: entry.ended_at ?? entry.started_at,
  };
}

interface ReplayContextValue {
  // Current state
  state: LoopState;
  currentEntry: RawIterationEntry | null;

  // Navigation
  entryIndex: number;
  totalEntries: number;
  nextEntry: () => void;
  prevEntry: () => void;
  goToEntry: (index: number) => void;

  // Playback
  autoPlay: boolean;
  setAutoPlay: (enabled: boolean) => void;
  playbackSpeed: number;
  setPlaybackSpeed: (speed: number) => void;

  // Loop selection
  availableLoops: string[];
  selectedLoop: string | null;
  selectLoop: (loopId: string) => void;

  // Loading state
  isLoading: boolean;
  error: string | null;
}

const ReplayContext = createContext<ReplayContextValue | null>(null);

interface ReplayProviderProps {
  children: ReactNode;
  initialLoop?: string;
}

/**
 * ReplayProvider - Replay historical loop iterations
 *
 * Loads iteration history from run-summary.json and allows
 * stepping through each iteration to see how the loop progressed.
 */
export function ReplayProvider({ children, initialLoop }: ReplayProviderProps) {
  const [entries, setEntries] = useState<RawIterationEntry[]>([]);
  const [entryIndex, setEntryIndex] = useState(0);
  const [availableLoops, setAvailableLoops] = useState<string[]>([]);
  const [selectedLoop, setSelectedLoop] = useState<string | null>(initialLoop ?? null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [autoPlay, setAutoPlay] = useState(false);
  const [playbackSpeed, setPlaybackSpeed] = useState(1000); // ms between entries

  // Load available loops on mount
  useEffect(() => {
    fetchLoopList().then((loops) => {
      setAvailableLoops(loops);
      if (!selectedLoop && loops.length > 0) {
        setSelectedLoop(loops[0]);
      }
    });
  }, [selectedLoop]);

  // Load entries when loop changes
  useEffect(() => {
    if (!selectedLoop) {
      setIsLoading(false);
      return;
    }

    setIsLoading(true);
    setError(null);

    fetchRunSummary(selectedLoop)
      .then((summary) => {
        if (summary?.entries) {
          setEntries(summary.entries);
          setEntryIndex(0);
        } else {
          setEntries([]);
          setError('No iteration history found');
        }
      })
      .catch((e) => {
        setError(e instanceof Error ? e.message : 'Failed to load history');
        setEntries([]);
      })
      .finally(() => {
        setIsLoading(false);
      });
  }, [selectedLoop]);

  const currentEntry = entries[entryIndex] ?? null;
  const state = currentEntry && selectedLoop
    ? entryToState(currentEntry, selectedLoop)
    : emptyState;

  const nextEntry = useCallback(() => {
    setEntryIndex((i) => Math.min(i + 1, entries.length - 1));
  }, [entries.length]);

  const prevEntry = useCallback(() => {
    setEntryIndex((i) => Math.max(i - 1, 0));
  }, []);

  const goToEntry = useCallback(
    (index: number) => {
      setEntryIndex(Math.max(0, Math.min(index, entries.length - 1)));
    },
    [entries.length]
  );

  const selectLoop = useCallback((loopId: string) => {
    setSelectedLoop(loopId);
    setEntryIndex(0);
  }, []);

  // Auto-play timer
  useEffect(() => {
    if (!autoPlay || entries.length === 0) return;

    // Stop at the end
    if (entryIndex >= entries.length - 1) {
      setAutoPlay(false);
      return;
    }

    const timer = setTimeout(nextEntry, playbackSpeed);
    return () => clearTimeout(timer);
  }, [autoPlay, playbackSpeed, nextEntry, entryIndex, entries.length]);

  return (
    <ReplayContext.Provider
      value={{
        state,
        currentEntry,
        entryIndex,
        totalEntries: entries.length,
        nextEntry,
        prevEntry,
        goToEntry,
        autoPlay,
        setAutoPlay,
        playbackSpeed,
        setPlaybackSpeed,
        availableLoops,
        selectedLoop,
        selectLoop,
        isLoading,
        error,
      }}
    >
      {children}
    </ReplayContext.Provider>
  );
}

/**
 * Hook to access replay state and controls
 */
export function useReplayState() {
  const context = useContext(ReplayContext);
  if (!context) {
    throw new Error('useReplayState must be used within ReplayProvider');
  }
  return context;
}
