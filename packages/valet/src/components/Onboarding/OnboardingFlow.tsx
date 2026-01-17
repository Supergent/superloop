import { useState } from 'react';
import { Welcome } from './Welcome';
import { AccountCreation } from './AccountCreation';
import { MoleCheck } from './MoleCheck';
import { Permissions } from './Permissions';
import { Shortcut } from './Shortcut';
import { FirstScan } from './FirstScan';
import { TrialResults } from './TrialResults';
import type { MoleStatusMetrics, MoleAnalyzeResult } from '../../lib/moleTypes';

export type OnboardingStep = 'welcome' | 'account-creation' | 'mole-check' | 'permissions' | 'shortcut' | 'first-scan' | 'trial-results' | 'complete';

interface OnboardingFlowProps {
  onComplete: () => void;
}

export function OnboardingFlow({ onComplete }: OnboardingFlowProps) {
  const [currentStep, setCurrentStep] = useState<OnboardingStep>('welcome');
  const [scanData, setScanData] = useState<{ metrics: MoleStatusMetrics; diskAnalysis: MoleAnalyzeResult } | null>(null);

  const handleNext = (data?: { metrics: MoleStatusMetrics; diskAnalysis: MoleAnalyzeResult }) => {
    // Store scan data if provided
    if (data) {
      setScanData(data);
    }

    switch (currentStep) {
      case 'welcome':
        setCurrentStep('account-creation');
        break;
      case 'account-creation':
        setCurrentStep('mole-check');
        break;
      case 'mole-check':
        setCurrentStep('permissions');
        break;
      case 'permissions':
        setCurrentStep('shortcut');
        break;
      case 'shortcut':
        setCurrentStep('first-scan');
        break;
      case 'first-scan':
        setCurrentStep('trial-results');
        break;
      case 'trial-results':
        setCurrentStep('complete');
        onComplete();
        break;
    }
  };

  const handleBack = () => {
    switch (currentStep) {
      case 'account-creation':
        setCurrentStep('welcome');
        break;
      case 'mole-check':
        setCurrentStep('account-creation');
        break;
      case 'permissions':
        setCurrentStep('mole-check');
        break;
      case 'shortcut':
        setCurrentStep('permissions');
        break;
      case 'first-scan':
        setCurrentStep('shortcut');
        break;
      case 'trial-results':
        setCurrentStep('first-scan');
        break;
    }
  };

  return (
    <div className="onboarding-flow">
      {currentStep === 'welcome' && (
        <Welcome onNext={handleNext} />
      )}
      {currentStep === 'account-creation' && (
        <AccountCreation onNext={handleNext} onBack={handleBack} />
      )}
      {currentStep === 'mole-check' && (
        <MoleCheck onNext={handleNext} onBack={handleBack} />
      )}
      {currentStep === 'permissions' && (
        <Permissions onNext={handleNext} onBack={handleBack} />
      )}
      {currentStep === 'shortcut' && (
        <Shortcut onNext={handleNext} onBack={handleBack} />
      )}
      {currentStep === 'first-scan' && (
        <FirstScan onNext={handleNext} onBack={handleBack} />
      )}
      {currentStep === 'trial-results' && (
        <TrialResults
          onNext={handleNext}
          onBack={handleBack}
          metrics={scanData?.metrics}
          diskAnalysis={scanData?.diskAnalysis}
        />
      )}
    </div>
  );
}
