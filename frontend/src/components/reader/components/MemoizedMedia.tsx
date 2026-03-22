/* eslint-disable @next/next/no-img-element */
import { memo, forwardRef } from 'react';
import type React from 'react';

type ImgFetchPriority = 'high' | 'low' | 'auto';

type MemoizedImageProps = Omit<React.ImgHTMLAttributes<HTMLImageElement>, 'fetchPriority'> & {
  fetchPriority?: ImgFetchPriority;
};

export const MemoizedImage = memo(
  forwardRef(function MemoizedImage(
    { src, alt, className, style, decoding, loading, fetchPriority, ...rest }: MemoizedImageProps,
    ref: React.ForwardedRef<HTMLImageElement>
  ) {
    return (
      <img
        ref={ref}
        src={src}
        alt={alt}
        className={className}
        style={style}
        decoding={decoding}
        loading={loading}
        fetchPriority={fetchPriority}
        {...rest}
      />
    );
  }),
  (prevProps, nextProps) => {
    // Ignore handler identity changes (onLoad/onError/etc) to reduce re-renders while paging/zooming.
    return (
      prevProps.src === nextProps.src &&
      prevProps.alt === nextProps.alt &&
      prevProps.className === nextProps.className &&
      prevProps.style === nextProps.style &&
      prevProps.decoding === nextProps.decoding &&
      prevProps.loading === nextProps.loading &&
      prevProps.fetchPriority === nextProps.fetchPriority
    );
  }
);

MemoizedImage.displayName = 'MemoizedImage';

export const MemoizedVideo = memo(
  forwardRef(function MemoizedVideo(
    {
      src,
      className,
      style,
      showNativeControls = false,
      onLoadedData,
      onError,
    }: {
      src: string;
      className?: string;
      style?: React.CSSProperties;
      showNativeControls?: boolean;
      onLoadedData?: () => void;
      onError?: () => void;
    },
    ref: React.ForwardedRef<HTMLVideoElement>
  ) {
    const handleTogglePlay = (e: React.MouseEvent<HTMLVideoElement>) => {
      e.stopPropagation();
      const video = e.currentTarget;
      if (video.paused) {
        void video.play().catch(() => {});
        return;
      }
      video.pause();
    };

    return (
      <video
        ref={ref}
        src={src}
        controls={showNativeControls}
        playsInline
        preload="metadata"
        className={className}
        style={style}
        onLoadedData={onLoadedData}
        onError={onError}
        onClick={showNativeControls ? undefined : handleTogglePlay}
        onTouchStart={(e) => {
          if (!showNativeControls) e.stopPropagation();
        }}
      />
    );
  })
);

MemoizedVideo.displayName = 'MemoizedVideo';
