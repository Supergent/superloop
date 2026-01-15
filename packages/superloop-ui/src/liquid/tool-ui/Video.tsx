/**
 * Video - Video playback with controls
 * Ported from: https://github.com/assistant-ui/tool-ui
 *
 * Adapted for json-render integration
 */

import * as React from "react";
import type { ComponentRenderProps } from "@json-render/react";
import { Play } from "lucide-react";
import { cn } from "../../lib/cn.js";
import { Button } from "../../ui/button.js";
import {
  ActionButtons,
  normalizeActionsConfig,
  RATIO_CLASS_MAP,
  type ActionsProp,
} from "./shared/index.js";

interface VideoProps {
  id?: string;
  src: string;
  poster?: string;
  title?: string;
  ratio?: "auto" | "1:1" | "4:3" | "16:9" | "3:2" | "9:16";
  autoPlay?: boolean;
  muted?: boolean;
  controls?: boolean;
  loop?: boolean;
  locale?: string;
  responseActions?: ActionsProp;
  isLoading?: boolean;
  className?: string;
}

const FALLBACK_LOCALE = "en-US";

const OVERLAY_GRADIENT =
  "linear-gradient(to bottom, rgba(0,0,0,0.7) 0%, rgba(0,0,0,0) 100%)";

function VideoProgress() {
  return (
    <div className="flex w-full animate-pulse flex-col gap-3">
      <div className="bg-muted aspect-video w-full rounded-lg" />
    </div>
  );
}

export function Video({ element, onAction }: ComponentRenderProps) {
  const props = element.props as unknown as VideoProps;
  const {
    id,
    src,
    poster,
    title,
    ratio = "16:9",
    autoPlay = false,
    muted = true,
    controls = true,
    loop = false,
    locale: providedLocale,
    responseActions,
    isLoading,
    className,
  } = props;

  const locale = providedLocale ?? FALLBACK_LOCALE;
  const videoRef = React.useRef<HTMLVideoElement | null>(null);
  const [isPlaying, setIsPlaying] = React.useState(false);

  const normalizedActions = React.useMemo(
    () => normalizeActionsConfig(responseActions),
    [responseActions],
  );

  const handleWatch = (event: React.MouseEvent<HTMLButtonElement>) => {
    event.preventDefault();
    event.stopPropagation();
    const video = videoRef.current;
    if (!video) return;
    if (video.paused) {
      void video.play().catch(() => undefined);
    } else {
      video.pause();
    }
  };

  const handleResponseAction = React.useCallback(
    (actionId: string) => {
      onAction?.({ name: actionId });
    },
    [onAction],
  );

  return (
    <article
      className={cn("relative w-full min-w-80 max-w-md", className)}
      lang={locale}
      aria-busy={isLoading}
      data-tool-ui-id={id}
      data-slot="video"
    >
      <div
        className={cn(
          "group relative isolate flex w-full min-w-0 flex-col overflow-hidden rounded-xl",
          "border border-border bg-card text-sm shadow-sm",
        )}
      >
        {isLoading ? (
          <VideoProgress />
        ) : (
          <div
            className={cn(
              "group relative w-full overflow-hidden bg-black",
              ratio !== "auto" ? RATIO_CLASS_MAP[ratio] : "aspect-video",
            )}
          >
            <video
              ref={videoRef}
              className={cn(
                "relative z-10 h-full w-full object-cover transition-transform duration-300 group-hover:scale-[1.01]",
                ratio !== "auto" && "absolute inset-0 h-full w-full",
              )}
              src={src}
              poster={poster}
              controls={controls}
              playsInline
              autoPlay={autoPlay}
              preload="metadata"
              muted={muted}
              loop={loop}
              onPlay={() => {
                setIsPlaying(true);
                onAction?.({ name: "play", params: { id } });
              }}
              onPause={() => {
                setIsPlaying(false);
                onAction?.({ name: "pause", params: { id } });
              }}
            />
            {title && (
              <>
                <div
                  className="pointer-events-none absolute inset-x-0 top-0 z-20 h-32 opacity-0 transition-opacity duration-200 group-hover:opacity-100"
                  style={{ backgroundImage: OVERLAY_GRADIENT }}
                />
                <div className="absolute inset-x-0 top-0 z-30 flex items-start justify-between px-5 pt-4 opacity-0 transition-opacity duration-200 group-hover:opacity-100">
                  <div className="line-clamp-2 max-w-[70%] font-semibold text-white drop-shadow-sm">
                    {title}
                  </div>
                  <Button
                    variant="default"
                    size="sm"
                    onClick={handleWatch}
                    className="shadow-sm"
                  >
                    <Play className="mr-1 h-4 w-4" aria-hidden="true" />
                    {isPlaying ? "Pause" : "Watch"}
                  </Button>
                </div>
              </>
            )}
          </div>
        )}
      </div>
      {normalizedActions && (
        <div className="mt-3">
          <ActionButtons
            actions={normalizedActions.items}
            align={normalizedActions.align}
            confirmTimeout={normalizedActions.confirmTimeout}
            onAction={handleResponseAction}
          />
        </div>
      )}
    </article>
  );
}
