import { useState } from 'react';
import { Welcome } from './Welcome';
import { MoleCheck } from './MoleCheck';
import { Permissions } from './Permissions';
import { Shortcut } from './Shortcut';
import { FirstScan } from './FirstScan';

export type OnboardingStep = 'welcome' | 'mole-check' | 'permissions' | 'shortcut' | 'first-scan' | 'complete';

interface OnboardingFlowProps {
  onComplete: () => void;
}

export function OnboardingFlow({ onComplete }: OnboardingFlowProps) {
  const [currentStep, setCurrentStep] = useState<OnboardingStep>('welcome');

  const handleNext = () => {
    switch (currentStep) {
      case 'welcome':
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
        setCurrentStep('complete');
        onComplete();
        break;
    }
  };

  const handleBack = () => {
    switch (currentStep) {
      case 'mole-check':
        setCurrentStep('welcome');
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
    }
  };

  return (
    <div className="onboarding-flow">
      {currentStep === 'welcome' && (
        <Welcome onNext={handleNext} />
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
    </div>
  );
}
