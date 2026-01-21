import {
  createContext,
  useContext,
  useState,
  useEffect,
  useCallback,
  type ReactNode,
} from 'react';
import { type LoopState, emptyState } from '../types';
import { loadLoopState, fetchLoopList } from './loader';

interface LiveContextValue {
  state: LoopState;
  availableLoops: string[];
  selectedLoop: string | null;
  selectLoop: (loopId: string) => void;
  isLoading: boolean;
  error: string | null;
  refresh: () => Promise<void>;
  pollInterval: number;
  setPollInterval: (ms: number) => void;
}

const LiveContext = createContext<LiveContextValue | null>(null);

interface LiveProviderProps {
  children: ReactNode;
  initialPollInterval?: number;
}

/**
 * LiveProvider - Real-time data from .superloop directory
 *
 * Polls the Vite API endpoints for current loop state.
 * Supports switching between available loops.
 */
export function LiveProvider({
  children,
  initialPollInterval = 2000,
}: LiveProviderProps) {
  const [state, setState] = useState<LoopState>(emptyState);
  const [availableLoops, setAvailableLoops] = useState<string[]>([]);
  const [selectedLoop, setSelectedLoop] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [pollInterval, setPollInterval] = useState(initialPollInterval);

  const refresh = useCallback(async () => {
    try {
      setError(null);
      const [newState, loops] = await Promise.all([
        loadLoopState(selectedLoop ?? undefined),
        fetchLoopList(),
      ]);
      setState(newState);
      setAvailableLoops(loops);

      // Auto-select current loop if none selected
      if (!selectedLoop && newState.loopId) {
        setSelectedLoop(newState.loopId);
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load state');
    } finally {
      setIsLoading(false);
    }
  }, [selectedLoop]);

  const selectLoop = useCallback((loopId: string) => {
    setSelectedLoop(loopId);
  }, []);

  // Initial load
  useEffect(() => {
    refresh();
  }, [refresh]);

  // Polling
  useEffect(() => {
    if (pollInterval <= 0) return;

    const timer = setInterval(refresh, pollInterval);
    return () => clearInterval(timer);
  }, [pollInterval, refresh]);

  return (
    <LiveContext.Provider
      value={{
        state,
        availableLoops,
        selectedLoop,
        selectLoop,
        isLoading,
        error,
        refresh,
        pollInterval,
        setPollInterval,
      }}
    >
      {children}
    </LiveContext.Provider>
  );
}

/**
 * Hook to access live loop state
 */
export function useLiveState() {
  const context = useContext(LiveContext);
  if (!context) {
    throw new Error('useLiveState must be used within LiveProvider');
  }
  return context;
}
