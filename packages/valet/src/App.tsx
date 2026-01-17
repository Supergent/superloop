import { useState, useEffect, useCallback, useRef } from 'react';
import './App.css';
import { MenubarDropdown } from './components/MenubarDropdown';
import { MetricsDisplay } from './components/MetricsDisplay';
import { QuickActions } from './components/QuickActions';
import { ActivityLog, ActivityLogEntry } from './components/ActivityLog';
import { VoiceInput, VoiceInputRef } from './components/VoiceInput';
import { VoicePlaybackControls } from './components/VoicePlaybackControls';
import { VoiceConversation, ConversationTurn } from './components/VoiceConversation';
import { ConfirmDialog } from './components/ConfirmDialog';
import { OnboardingFlow } from './components/Onboarding/OnboardingFlow';
import { useStatusPolling } from './hooks/useStatusPolling';
import { useVapiTts } from './hooks/useVapiTts';
import { useGlobalShortcut } from './hooks/useGlobalShortcut';
import { computeHealthState } from './lib/health';
import { updateTray } from './lib/tray';
import { getAuditEvents, convertToActivityLogEntries, logAuditEvent } from './lib/audit';
import { analyzeDiskUsage, cleanSystem, optimizeSystem } from './lib/mole';
import { formatBytes } from './lib/formatters';
import { queryAgent, configureAgent } from './lib/agent';
import { isOnboardingComplete, completeOnboarding } from './lib/onboarding';
import { getAllKeys } from './lib/keys';
import { ConfirmationRequiredError, approveCommand, revokeApproval } from './lib/agentPolicy';
import { classifyIntent, intentToPrompt, detectConfirmation } from './lib/voice/intent';
import { getSetting } from './lib/settings';
import type { StreamMessage } from '@anthropic-ai/claude-agent-sdk';
import type { MoleAnalyzeResult, MoleCleanResult, MoleOptimizeResult } from './lib/moleTypes';

interface ConfirmState {
  open: boolean;
  title: string;
  message: string;
  details?: string[];
  action: () => Promise<void>;
  actionType: 'clean' | 'optimize' | 'scan' | 'agent-command';
}

function App() {
  // Onboarding state
  const [onboardingComplete, setOnboardingComplete] = useState<boolean | null>(null);

  // Status polling and health
  const { metrics, loading, error, lastUpdate } = useStatusPolling();
  const health = metrics ? computeHealthState(metrics) : null;

  // Activity log state
  const [activityEntries, setActivityEntries] = useState<ActivityLogEntry[]>([]);

  // Confirm dialog state
  const [confirmState, setConfirmState] = useState<ConfirmState>({
    open: false,
    title: '',
    message: '',
    action: async () => {},
    actionType: 'clean',
  });

  // State to track pending voice query that needs confirmation
  const [pendingVoiceQuery, setPendingVoiceQuery] = useState<{
    prompt: string;
    command: string;
  } | null>(null);

  // Action state
  const [isPerformingAction, setIsPerformingAction] = useState(false);

  // AI & Voice state
  const [isAiWorking, setIsAiWorking] = useState(false);
  const [aiResponse, setAiResponse] = useState('');
  const [currentSessionId, setCurrentSessionId] = useState<string | undefined>();

  // API Keys state
  const [assemblyAiApiKey, setAssemblyAiApiKey] = useState<string>('');
  const [vapiPublicKey, setVapiPublicKey] = useState<string>('');
  const [llmProxyApiKey, setLlmProxyApiKey] = useState<string>('');

  // Voice activation setting
  const [voiceEnabled, setVoiceEnabled] = useState<boolean>(true);

  const [ttsState, ttsActions] = useVapiTts({ publicKey: vapiPublicKey });

  // Voice input ref for programmatic control
  const voiceInputRef = useRef<VoiceInputRef>(null);
  const [isListening, setIsListening] = useState(false);
  const [isSpeaking, setIsSpeaking] = useState(false);

  // Conversation history
  const [conversationTurns, setConversationTurns] = useState<ConversationTurn[]>([]);

  // Load API keys function (reusable)
  const loadApiKeys = useCallback(async () => {
    try {
      const keys = await getAllKeys();
      setAssemblyAiApiKey(keys.assemblyAi || '');
      setVapiPublicKey(keys.vapiPublic || '');
      setLlmProxyApiKey(keys.llmProxy || '');
    } catch (error) {
      console.error('Failed to load API keys:', error);
    }
  }, []);

  // Load API keys on mount
  useEffect(() => {
    loadApiKeys();
  }, [loadApiKeys]);

  // Listen for API key changes and reload
  useEffect(() => {
    const handleKeysChanged = () => {
      loadApiKeys();
    };

    window.addEventListener('api-keys-changed', handleKeysChanged);
    return () => {
      window.removeEventListener('api-keys-changed', handleKeysChanged);
    };
  }, [loadApiKeys]);

  // Configure agent when llm-proxy API key changes
  useEffect(() => {
    // Always configure agent, even when key is cleared/empty
    // This ensures the agent config is reset when the key is deleted
    configureAgent({ apiKey: llmProxyApiKey || undefined });
  }, [llmProxyApiKey]);

  // Load voice enabled setting on mount
  useEffect(() => {
    const loadVoiceEnabled = async () => {
      try {
        const setting = await getSetting('voiceEnabled');
        setVoiceEnabled(setting !== 'false'); // Default to true if not set
      } catch (error) {
        console.error('Failed to load voice enabled setting:', error);
        setVoiceEnabled(true); // Default to true on error
      }
    };
    loadVoiceEnabled();

    // Listen for setting changes
    const handleSettingChange = (event: Event) => {
      const customEvent = event as CustomEvent<{ key: string; value: string }>;
      if (customEvent.detail?.key === 'voiceEnabled') {
        setVoiceEnabled(customEvent.detail.value !== 'false');
      }
    };

    window.addEventListener('setting-changed', handleSettingChange);
    return () => {
      window.removeEventListener('setting-changed', handleSettingChange);
    };
  }, []);

  // Check onboarding status on mount
  useEffect(() => {
    const checkOnboarding = async () => {
      const complete = await isOnboardingComplete();
      setOnboardingComplete(complete);
    };
    checkOnboarding();
  }, []);

  // Handle onboarding completion
  const handleOnboardingComplete = async () => {
    await completeOnboarding();
    setOnboardingComplete(true);
  };

  // Update tray whenever health or lastUpdate changes
  useEffect(() => {
    if (health) {
      updateTray(health, lastUpdate).catch(console.error);
    }
  }, [health, lastUpdate]);

  // Load initial activity log
  useEffect(() => {
    const loadActivityLog = async () => {
      const events = await getAuditEvents(10);
      setActivityEntries(convertToActivityLogEntries(events));
    };
    loadActivityLog();
  }, []);

  // Refresh activity log after actions
  const refreshActivityLog = async () => {
    const events = await getAuditEvents(10);
    setActivityEntries(convertToActivityLogEntries(events));
  };

  // Clean action handler
  const handleClean = async () => {
    try {
      // First, run dry-run to get preview
      const dryRunResult = await cleanSystem({ dryRun: true });

      const details = [
        `Items to remove: ${dryRunResult.itemsRemoved}`,
        `Space to recover: ${formatBytes(dryRunResult.spaceRecovered)}`,
        ...dryRunResult.categories.map(
          (cat) => `${cat.name}: ${formatBytes(cat.spaceRecovered)}`
        ),
      ];

      setConfirmState({
        open: true,
        title: 'Confirm Cleanup',
        message: 'The following cleanup will be performed:',
        details,
        actionType: 'clean',
        action: async () => {
          setIsPerformingAction(true);
          try {
            const result = await cleanSystem({ dryRun: false });
            await logAuditEvent(
              'command_executed',
              'mo clean',
              { exitCode: 0 }
            );
            await refreshActivityLog();
          } finally {
            setIsPerformingAction(false);
          }
        },
      });
    } catch (err) {
      console.error('Clean action failed:', err);
      await logAuditEvent(
        'command_executed',
        'mo clean',
        { exitCode: 1, reason: String(err) }
      );
    }
  };

  // Optimize action handler
  const handleOptimize = async () => {
    try {
      // First, run dry-run to get preview
      const dryRunResult = await optimizeSystem({ dryRun: true });

      const details = [
        `Tasks to perform: ${dryRunResult.tasksCompleted.length}`,
        ...dryRunResult.tasksCompleted.map((task) => `• ${task.name}`),
      ];

      if (dryRunResult.requiresSudo) {
        details.push('⚠️ Requires administrator privileges');
      }

      setConfirmState({
        open: true,
        title: 'Confirm Optimization',
        message: 'The following system optimizations will be performed:',
        details,
        actionType: 'optimize',
        action: async () => {
          setIsPerformingAction(true);
          try {
            const result = await optimizeSystem({ dryRun: false });
            const completedTasks = result.tasksCompleted.filter((t) => t.success).length;
            await logAuditEvent(
              'command_executed',
              'mo optimize',
              { exitCode: 0 }
            );
            await refreshActivityLog();
          } finally {
            setIsPerformingAction(false);
          }
        },
      });
    } catch (err) {
      console.error('Optimize action failed:', err);
      await logAuditEvent(
        'command_executed',
        'mo optimize',
        { exitCode: 1, reason: String(err) }
      );
    }
  };

  // Deep scan action handler
  const handleDeepScan = async () => {
    setIsPerformingAction(true);
    try {
      const result = await analyzeDiskUsage();
      await logAuditEvent(
        'command_executed',
        'mo analyze',
        { exitCode: 0 }
      );
      await refreshActivityLog();
    } catch (err) {
      console.error('Deep scan failed:', err);
      await logAuditEvent(
        'command_executed',
        'mo analyze',
        { exitCode: 1, reason: String(err) }
      );
    } finally {
      setIsPerformingAction(false);
    }
  };

  // Confirm dialog handlers
  const handleConfirm = async () => {
    setConfirmState((prev) => ({ ...prev, open: false }));
    await confirmState.action();
  };

  const handleCancel = () => {
    setConfirmState((prev) => ({ ...prev, open: false }));
    // Clear pending voice query if user cancels agent command confirmation
    if (confirmState.actionType === 'agent-command') {
      setPendingVoiceQuery(null);
    }
  };

  // Track speaking state from TTS
  useEffect(() => {
    setIsSpeaking(ttsState.isPlaying);
  }, [ttsState.isPlaying]);

  // Voice input handlers
  const handleVoiceStart = useCallback(() => {
    setIsListening(true);
    ttsActions.stop(); // Stop any ongoing TTS when user starts speaking
  }, [ttsActions]);

  const handleVoiceEnd = useCallback(() => {
    setIsListening(false);
  }, []);

  const handleInterimTranscript = useCallback((text: string) => {
    // Could display interim transcript in UI if desired
    console.log('Interim:', text);
  }, []);

  const handleFinalTranscript = useCallback(async (text: string) => {
    if (!text.trim()) return;

    // Block voice actions if llmProxyApiKey is missing
    if (!llmProxyApiKey) {
      console.error('Cannot process voice input: llm-proxy API key is missing');
      const errorMsg = 'Please configure your API key in settings to use voice features.';
      setAiResponse(errorMsg);
      if (vapiPublicKey) {
        await ttsActions.speak(errorMsg);
      }
      return;
    }

    // Check if there's a pending confirmation and user is responding with yes/no
    const confirmation = detectConfirmation(text);
    if (pendingVoiceQuery && confirmation) {
      if (confirmation === 'yes') {
        // User confirmed - close the dialog and trigger the action
        setConfirmState(prev => ({ ...prev, open: false }));
        await confirmState.action();
      } else {
        // User declined - close the dialog and clear pending state
        setConfirmState(prev => ({ ...prev, open: false }));
        setPendingVoiceQuery(null);

        // Speak a cancellation message
        const cancelMsg = 'Okay, I\'ve cancelled that operation.';
        setAiResponse(cancelMsg);
        if (vapiPublicKey) {
          await ttsActions.speak(cancelMsg);
        }
      }
      return;
    }

    setIsAiWorking(true);
    setAiResponse('');

    try {
      const textChunks: string[] = [];

      // Classify the intent and enhance the prompt
      const intent = classifyIntent(text);
      const enhancedPrompt = intentToPrompt(intent);

      console.log('Voice intent:', intent.intent, 'Confidence:', intent.confidence);

      // Add user turn to conversation
      const userTurn: ConversationTurn = {
        id: `user-${Date.now()}`,
        timestamp: Date.now(),
        role: 'user',
        text,
        intent: intent.intent,
      };
      setConversationTurns(prev => [...prev, userTurn]);

      // Query the agent with the enhanced prompt
      for await (const message of queryAgent({
        prompt: enhancedPrompt,
        sessionId: currentSessionId,
        timeout: 120000, // 2 minute timeout for voice interactions
        onMessage: (msg: StreamMessage) => {
          if (msg.type === 'text') {
            textChunks.push(msg.text);
            setAiResponse(textChunks.join(''));
          }
        },
        onError: (error: Error) => {
          console.error('Agent error:', error);
          logAuditEvent(
            'command_rejected',
            'voice interaction',
            { reason: `Agent error: ${error.message}` }
          );
        },
        onTimeout: () => {
          console.error('Agent query timed out');
          logAuditEvent(
            'command_rejected',
            'voice interaction',
            { reason: 'Agent query timed out' }
          );
          setAiResponse('Sorry, the request took too long. Please try again.');
        },
      })) {
        // Handle different message types
        if (message.type === 'text') {
          // Text messages are already handled in onMessage
        } else if (message.type === 'session_id') {
          // Store session ID for multi-turn conversations
          setCurrentSessionId(message.sessionId);
        }
      }

      const fullResponse = textChunks.join('');

      // Add assistant turn to conversation
      if (fullResponse) {
        const assistantTurn: ConversationTurn = {
          id: `assistant-${Date.now()}`,
          timestamp: Date.now(),
          role: 'assistant',
          text: fullResponse,
        };
        setConversationTurns(prev => [...prev, assistantTurn]);
      }

      // Speak the response via TTS
      if (fullResponse && vapiPublicKey) {
        await ttsActions.speak(fullResponse);
      }

      // Log the interaction
      await logAuditEvent(
        'command_approved',
        'voice interaction',
        { reason: `User: "${text}"` }
      );

    } catch (error) {
      console.error('Error processing voice input:', error);

      // Handle confirmation-required errors
      if (error instanceof ConfirmationRequiredError) {
        const { command, decision } = error;

        // If dry-run is required, run it first to get a preview
        if (decision.requiresDryRun && decision.dryRunCommand) {
          try {
            // Set AI working state to show we're running the dry-run
            setIsAiWorking(true);
            setAiResponse('Running dry-run preview...');

            const dryRunTextChunks: string[] = [];

            // Execute the dry-run command via the agent
            for await (const message of queryAgent({
              prompt: `Execute this command: ${decision.dryRunCommand}`,
              sessionId: currentSessionId,
              timeout: 60000,
              onMessage: (msg: StreamMessage) => {
                if (msg.type === 'text') {
                  dryRunTextChunks.push(msg.text);
                }
              },
            })) {
              if (message.type === 'session_id') {
                setCurrentSessionId(message.sessionId);
              }
            }

            const dryRunOutput = dryRunTextChunks.join('');

            // Build details with dry-run preview
            const details: string[] = [
              `Command: ${command}`,
              `Dry-run preview completed.`,
              decision.reason || '',
              '',
              'Preview results:',
              dryRunOutput,
            ];

            // Store the pending query for retry
            setPendingVoiceQuery({ prompt: text, command });

            // Show confirmation dialog with dry-run results
            setConfirmState({
              open: true,
              title: 'Confirm Destructive Command',
              message: 'Review the dry-run preview before proceeding:',
              details,
              actionType: 'agent-command',
              action: async () => {
                // Approve the command
                approveCommand(command);
                setPendingVoiceQuery(null);

                // Retry the query with the approved command
                setIsAiWorking(true);
                setAiResponse('');

                try {
                  const retryTextChunks: string[] = [];

                  // Classify intent and enhance prompt for retry
                  const retryIntent = classifyIntent(text);
                  const retryEnhancedPrompt = intentToPrompt(retryIntent);

                  // Query the agent again with the approved command
                  for await (const message of queryAgent({
                    prompt: retryEnhancedPrompt,
                    sessionId: currentSessionId,
                    timeout: 120000,
                    onMessage: (msg: StreamMessage) => {
                      if (msg.type === 'text') {
                        retryTextChunks.push(msg.text);
                        setAiResponse(retryTextChunks.join(''));
                      }
                    },
                    onError: (error: Error) => {
                      console.error('Agent error on retry:', error);
                      logAuditEvent(
                        'command_rejected',
                        'voice interaction retry',
                        { reason: `Agent error: ${error.message}` }
                      );
                    },
                    onTimeout: () => {
                      console.error('Agent query timed out on retry');
                      logAuditEvent(
                        'command_rejected',
                        'voice interaction retry',
                        { reason: 'Agent query timed out' }
                      );
                      setAiResponse('Sorry, the request took too long. Please try again.');
                    },
                  })) {
                    if (message.type === 'session_id') {
                      setCurrentSessionId(message.sessionId);
                    }
                  }

                  const fullResponse = retryTextChunks.join('');

                  // Add assistant turn to conversation
                  if (fullResponse) {
                    const assistantTurn: ConversationTurn = {
                      id: `assistant-${Date.now()}`,
                      timestamp: Date.now(),
                      role: 'assistant',
                      text: fullResponse,
                    };
                    setConversationTurns(prev => [...prev, assistantTurn]);
                  }

                  // Speak the response via TTS
                  if (fullResponse && vapiPublicKey) {
                    await ttsActions.speak(fullResponse);
                  }

                  // Log the interaction
                  await logAuditEvent(
                    'command_approved',
                    'voice interaction retry',
                    { reason: `User: "${text}" (after confirmation)` }
                  );

                  // Consume the approval after successful execution
                  revokeApproval(command);
                } catch (retryError) {
                  console.error('Error on retry:', retryError);
                  const errorMsg = 'Sorry, I encountered an error processing your request.';
                  setAiResponse(errorMsg);
                  if (vapiPublicKey) {
                    await ttsActions.speak(errorMsg);
                  }
                } finally {
                  setIsAiWorking(false);
                }
              },
            });

            // Don't show a generic error - the confirmation dialog is showing
            setIsAiWorking(false);
          } catch (dryRunError) {
            console.error('Error running dry-run preview:', dryRunError);
            // Fall back to showing confirmation without preview
            const details: string[] = [
              `Command: ${command}`,
              `Failed to run dry-run preview: ${dryRunError instanceof Error ? dryRunError.message : String(dryRunError)}`,
              decision.reason || '',
            ];

            setPendingVoiceQuery({ prompt: text, command });

            setConfirmState({
              open: true,
              title: 'Confirm Command',
              message: 'The agent wants to execute the following command:',
              details,
              actionType: 'agent-command',
              action: async () => {
                // Same retry logic as above
                approveCommand(command);
                setPendingVoiceQuery(null);
                setIsAiWorking(true);
                setAiResponse('');

                try {
                  const retryTextChunks: string[] = [];
                  const retryIntent = classifyIntent(text);
                  const retryEnhancedPrompt = intentToPrompt(retryIntent);

                  for await (const message of queryAgent({
                    prompt: retryEnhancedPrompt,
                    sessionId: currentSessionId,
                    timeout: 120000,
                    onMessage: (msg: StreamMessage) => {
                      if (msg.type === 'text') {
                        retryTextChunks.push(msg.text);
                        setAiResponse(retryTextChunks.join(''));
                      }
                    },
                  })) {
                    if (message.type === 'session_id') {
                      setCurrentSessionId(message.sessionId);
                    }
                  }

                  const fullResponse = retryTextChunks.join('');
                  if (fullResponse) {
                    setConversationTurns(prev => [...prev, {
                      id: `assistant-${Date.now()}`,
                      timestamp: Date.now(),
                      role: 'assistant',
                      text: fullResponse,
                    }]);
                  }

                  if (fullResponse && vapiPublicKey) {
                    await ttsActions.speak(fullResponse);
                  }

                  await logAuditEvent(
                    'command_approved',
                    'voice interaction retry',
                    { reason: `User: "${text}" (after confirmation)` }
                  );

                  // Consume the approval after successful execution
                  revokeApproval(command);
                } catch (retryError) {
                  console.error('Error on retry:', retryError);
                  const errorMsg = 'Sorry, I encountered an error processing your request.';
                  setAiResponse(errorMsg);
                  if (vapiPublicKey) {
                    await ttsActions.speak(errorMsg);
                  }
                } finally {
                  setIsAiWorking(false);
                }
              },
            });

            setIsAiWorking(false);
          }
        } else {
          // No dry-run required, just show confirmation
          const details: string[] = [
            `Command: ${command}`,
            decision.reason || '',
          ];

          setPendingVoiceQuery({ prompt: text, command });

          setConfirmState({
            open: true,
            title: 'Confirm Command',
            message: 'The agent wants to execute the following command:',
            details,
            actionType: 'agent-command',
            action: async () => {
              // Same retry logic as above
              approveCommand(command);
              setPendingVoiceQuery(null);
              setIsAiWorking(true);
              setAiResponse('');

              try {
                const retryTextChunks: string[] = [];
                const retryIntent = classifyIntent(text);
                const retryEnhancedPrompt = intentToPrompt(retryIntent);

                for await (const message of queryAgent({
                  prompt: retryEnhancedPrompt,
                  sessionId: currentSessionId,
                  timeout: 120000,
                  onMessage: (msg: StreamMessage) => {
                    if (msg.type === 'text') {
                      retryTextChunks.push(msg.text);
                      setAiResponse(retryTextChunks.join(''));
                    }
                  },
                })) {
                  if (message.type === 'session_id') {
                    setCurrentSessionId(message.sessionId);
                  }
                }

                const fullResponse = retryTextChunks.join('');
                if (fullResponse) {
                  setConversationTurns(prev => [...prev, {
                    id: `assistant-${Date.now()}`,
                    timestamp: Date.now(),
                    role: 'assistant',
                    text: fullResponse,
                  }]);
                }

                if (fullResponse && vapiPublicKey) {
                  await ttsActions.speak(fullResponse);
                }

                await logAuditEvent(
                  'command_approved',
                  'voice interaction retry',
                  { reason: `User: "${text}" (after confirmation)` }
                );

                // Consume the approval after successful execution
                const { revokeApproval } = await import('./lib/agentPolicy');
                revokeApproval(command);
              } catch (retryError) {
                console.error('Error on retry:', retryError);
                const errorMsg = 'Sorry, I encountered an error processing your request.';
                setAiResponse(errorMsg);
                if (vapiPublicKey) {
                  await ttsActions.speak(errorMsg);
                }
              } finally {
                setIsAiWorking(false);
              }
            },
          });

          setIsAiWorking(false);
        }

        return;
      }

      // Handle other errors
      const errorMsg = 'Sorry, I encountered an error processing your request.';
      setAiResponse(errorMsg);
      if (vapiPublicKey) {
        await ttsActions.speak(errorMsg);
      }
    } finally {
      setIsAiWorking(false);
    }
  }, [currentSessionId, vapiPublicKey, llmProxyApiKey, ttsActions, pendingVoiceQuery, confirmState]);

  // Global shortcut for voice activation (Cmd+Shift+Space)
  useGlobalShortcut({
    shortcut: 'CommandOrControl+Shift+Space',
    onTrigger: () => {
      // Toggle voice input via ref
      if (voiceInputRef.current) {
        voiceInputRef.current.toggle();
      }
    },
    enabled: !!assemblyAiApiKey && voiceEnabled, // Only enable if API key is configured and voice is enabled
  });

  // Show loading state while checking onboarding
  if (onboardingComplete === null) {
    return (
      <div className="app app-loading">
        <div className="loading-spinner">Loading...</div>
      </div>
    );
  }

  // Show onboarding flow if not complete
  if (!onboardingComplete) {
    return (
      <div className="app">
        <OnboardingFlow onComplete={handleOnboardingComplete} />
      </div>
    );
  }

  // Show main app UI
  return (
    <div className="app">
      <MenubarDropdown
        health={health?.status || 'good'}
        metrics={metrics}
        loading={loading}
        error={error}
        aiWorking={isAiWorking}
        aiResponse={aiResponse}
        metricsSlot={metrics ? <MetricsDisplay metrics={metrics} /> : null}
        actionsSlot={
          <QuickActions
            onClean={handleClean}
            onOptimize={handleOptimize}
            onDeepScan={handleDeepScan}
            disabled={isPerformingAction || loading}
          />
        }
        voiceSlot={
          <>
            <VoiceInput
              ref={voiceInputRef}
              apiKey={assemblyAiApiKey}
              onVoiceStart={handleVoiceStart}
              onVoiceEnd={handleVoiceEnd}
              onInterimTranscript={handleInterimTranscript}
              onFinalTranscript={handleFinalTranscript}
              disabled={isPerformingAction || isAiWorking || !voiceEnabled || !llmProxyApiKey}
            />
            <VoicePlaybackControls
              state={ttsState}
              actions={ttsActions}
            />
            <VoiceConversation
              turns={conversationTurns}
              maxTurns={6}
            />
          </>
        }
        activitySlot={<ActivityLog entries={activityEntries} />}
      />

      <ConfirmDialog
        open={confirmState.open}
        title={confirmState.title}
        message={confirmState.message}
        details={confirmState.details}
        onConfirm={handleConfirm}
        onCancel={handleCancel}
        destructive={confirmState.actionType === 'clean'}
      />
    </div>
  );
}

export default App;
