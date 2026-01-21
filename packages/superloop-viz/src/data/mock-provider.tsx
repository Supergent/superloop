import {
  createContext,
  useContext,
  useState,
  useCallback,
  useEffect,
  type ReactNode,
} from 'react';
import { type LoopState, emptyState } from '../types';

/**
 * Demo states that simulate a full loop cycle
 */
const DEMO_STATES: LoopState[] = [
  // 1. Idle - loop not started
  {
    ...emptyState,
    status: 'idle',
    loopId: 'demo-loop',
  },

  // 2. In progress - iteration 1, planner phase
  {
    status: 'in_progress',
    loopId: 'demo-loop',
    iteration: 1,
    phase: 'planner',
    gates: {
      promise: 'pending',
      tests: 'pending',
      checklist: 'pending',
      evidence: 'pending',
      approval: 'pending',
    },
    stuckCount: 0,
    stuckReason: null,
    updatedAt: new Date().toISOString(),
  },

  // 3. In progress - iteration 1, implementer phase
  {
    status: 'in_progress',
    loopId: 'demo-loop',
    iteration: 1,
    phase: 'implementer',
    gates: {
      promise: 'passed',
      tests: 'pending',
      checklist: 'pending',
      evidence: 'pending',
      approval: 'pending',
    },
    stuckCount: 0,
    stuckReason: null,
    updatedAt: new Date().toISOString(),
  },

  // 4. In progress - iteration 1, tester phase
  {
    status: 'in_progress',
    loopId: 'demo-loop',
    iteration: 1,
    phase: 'tester',
    gates: {
      promise: 'passed',
      tests: 'pending',
      checklist: 'pending',
      evidence: 'pending',
      approval: 'pending',
    },
    stuckCount: 0,
    stuckReason: null,
    updatedAt: new Date().toISOString(),
  },

  // 5. Test failures - tests failed
  {
    status: 'in_progress',
    loopId: 'demo-loop',
    iteration: 1,
    phase: 'tester',
    gates: {
      promise: 'passed',
      tests: 'failed',
      checklist: 'pending',
      evidence: 'pending',
      approval: 'pending',
    },
    stuckCount: 0,
    stuckReason: null,
    updatedAt: new Date().toISOString(),
  },

  // 6. Back to implementer - iteration 2
  {
    status: 'in_progress',
    loopId: 'demo-loop',
    iteration: 2,
    phase: 'implementer',
    gates: {
      promise: 'passed',
      tests: 'pending',
      checklist: 'pending',
      evidence: 'pending',
      approval: 'pending',
    },
    stuckCount: 0,
    stuckReason: null,
    updatedAt: new Date().toISOString(),
  },

  // 7. Tester again - iteration 2
  {
    status: 'in_progress',
    loopId: 'demo-loop',
    iteration: 2,
    phase: 'tester',
    gates: {
      promise: 'passed',
      tests: 'passed',
      checklist: 'pending',
      evidence: 'pending',
      approval: 'pending',
    },
    stuckCount: 0,
    stuckReason: null,
    updatedAt: new Date().toISOString(),
  },

  // 8. Reviewer phase
  {
    status: 'in_progress',
    loopId: 'demo-loop',
    iteration: 2,
    phase: 'reviewer',
    gates: {
      promise: 'passed',
      tests: 'passed',
      checklist: 'passed',
      evidence: 'passed',
      approval: 'pending',
    },
    stuckCount: 0,
    stuckReason: null,
    updatedAt: new Date().toISOString(),
  },

  // 9. Awaiting approval
  {
    status: 'awaiting_approval',
    loopId: 'demo-loop',
    iteration: 2,
    phase: 'reviewer',
    gates: {
      promise: 'passed',
      tests: 'passed',
      checklist: 'passed',
      evidence: 'passed',
      approval: 'pending',
    },
    stuckCount: 0,
    stuckReason: null,
    updatedAt: new Date().toISOString(),
  },

  // 10. Complete
  {
    status: 'complete',
    loopId: 'demo-loop',
    iteration: 2,
    phase: 'reviewer',
    gates: {
      promise: 'passed',
      tests: 'passed',
      checklist: 'passed',
      evidence: 'passed',
      approval: 'passed',
    },
    stuckCount: 0,
    stuckReason: null,
    updatedAt: new Date().toISOString(),
  },
];

/**
 * Stuck states for demonstrating stuck detection
 */
const STUCK_STATES: LoopState[] = [
  {
    status: 'in_progress',
    loopId: 'demo-loop',
    iteration: 3,
    phase: 'implementer',
    gates: {
      promise: 'passed',
      tests: 'failed',
      checklist: 'pending',
      evidence: 'pending',
      approval: 'pending',
    },
    stuckCount: 1,
    stuckReason: 'No file changes detected',
    updatedAt: new Date().toISOString(),
  },
  {
    status: 'stuck',
    loopId: 'demo-loop',
    iteration: 4,
    phase: 'implementer',
    gates: {
      promise: 'passed',
      tests: 'failed',
      checklist: 'pending',
      evidence: 'pending',
      approval: 'pending',
    },
    stuckCount: 3,
    stuckReason: 'No file changes detected for 3 consecutive iterations',
    updatedAt: new Date().toISOString(),
  },
];

interface MockContextValue {
  state: LoopState;
  stateIndex: number;
  totalStates: number;
  nextState: () => void;
  prevState: () => void;
  goToState: (index: number) => void;
  setAutoPlay: (enabled: boolean) => void;
  autoPlay: boolean;
  showStuck: boolean;
  setShowStuck: (show: boolean) => void;
}

const MockContext = createContext<MockContextValue | null>(null);

interface MockProviderProps {
  children: ReactNode;
  autoPlayInterval?: number;
}

/**
 * MockProvider - Demo mode with timed transitions
 *
 * Provides state cycling through demo states.
 * Supports manual stepping (keyboard) and auto-play mode.
 */
export function MockProvider({ children, autoPlayInterval = 2000 }: MockProviderProps) {
  const [stateIndex, setStateIndex] = useState(0);
  const [autoPlay, setAutoPlay] = useState(false);
  const [showStuck, setShowStuck] = useState(false);

  const states = showStuck ? [...DEMO_STATES.slice(0, 6), ...STUCK_STATES] : DEMO_STATES;
  const state = states[stateIndex] ?? emptyState;

  const nextState = useCallback(() => {
    setStateIndex((i) => (i + 1) % states.length);
  }, [states.length]);

  const prevState = useCallback(() => {
    setStateIndex((i) => (i - 1 + states.length) % states.length);
  }, [states.length]);

  const goToState = useCallback(
    (index: number) => {
      setStateIndex(Math.max(0, Math.min(index, states.length - 1)));
    },
    [states.length]
  );

  // Auto-play timer
  useEffect(() => {
    if (!autoPlay) return;

    const timer = setInterval(nextState, autoPlayInterval);
    return () => clearInterval(timer);
  }, [autoPlay, autoPlayInterval, nextState]);

  // Reset index when switching stuck mode
  useEffect(() => {
    setStateIndex(0);
  }, [showStuck]);

  return (
    <MockContext.Provider
      value={{
        state,
        stateIndex,
        totalStates: states.length,
        nextState,
        prevState,
        goToState,
        autoPlay,
        setAutoPlay,
        showStuck,
        setShowStuck,
      }}
    >
      {children}
    </MockContext.Provider>
  );
}

/**
 * Hook to access mock state and controls
 */
export function useMockState() {
  const context = useContext(MockContext);
  if (!context) {
    throw new Error('useMockState must be used within MockProvider');
  }
  return context;
}
