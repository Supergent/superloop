import { useRef, useEffect, useCallback } from 'react';
import { createLayout, stagger } from 'animejs';

interface AnimateOptions {
  duration?: number;
  delay?: number | ReturnType<typeof stagger>;
  ease?: string;
}

const defaultOptions = {
  duration: 500,
  delay: stagger(50),
  ease: 'outExpo',
};

/**
 * React hook for Anime.js Layout FLIP animations.
 *
 * Wraps createLayout() to provide smooth animations when DOM changes occur.
 * Call animateTransition with a function that updates state - the layout
 * system will capture before/after positions and animate the transition.
 */
export function useAnimeLayout(selector: string) {
  const layoutRef = useRef<ReturnType<typeof createLayout> | null>(null);

  useEffect(() => {
    // Create layout instance for the selector
    layoutRef.current = createLayout(selector);

    return () => {
      // Cleanup on unmount
      layoutRef.current?.revert();
    };
  }, [selector]);

  const animateTransition = useCallback(
    (updateFn: () => void, options: AnimateOptions = {}) => {
      const mergedOptions = { ...defaultOptions, ...options };

      if (layoutRef.current) {
        layoutRef.current.update(updateFn, {
          duration: mergedOptions.duration,
          delay: mergedOptions.delay,
          ease: mergedOptions.ease,
        });
      } else {
        // Fallback: just run the update without animation
        updateFn();
      }
    },
    []
  );

  return { animateTransition };
}

/**
 * Simple hook for basic anime.js animations without layout.
 * Use this for simpler value-based animations.
 */
export function useAnimate() {
  const animate = useCallback(
    async (
      targets: string | Element | Element[],
      properties: Record<string, unknown>,
      options: { duration?: number; ease?: string } = {}
    ) => {
      const { animate: animeAnimate } = await import('animejs');
      return animeAnimate(targets, {
        ...properties,
        duration: options.duration ?? 500,
        ease: options.ease ?? 'outExpo',
      });
    },
    []
  );

  return { animate };
}
