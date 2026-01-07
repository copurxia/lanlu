import Image from 'next/image';
import { memo, forwardRef } from 'react';
import type React from 'react';

export const MemoizedImage = memo(Image, (prevProps, nextProps) => {
  return (
    prevProps.src === nextProps.src &&
    prevProps.fill === nextProps.fill &&
    prevProps.className === nextProps.className &&
    prevProps.style === nextProps.style
  );
});

MemoizedImage.displayName = 'MemoizedImage';

export const MemoizedVideo = memo(
  forwardRef(function MemoizedVideo(
    {
      src,
      className,
      style,
      onLoadedData,
      onError,
    }: {
      src: string;
      className?: string;
      style?: React.CSSProperties;
      onLoadedData?: () => void;
      onError?: () => void;
    },
    ref: React.ForwardedRef<HTMLVideoElement>
  ) {
    return (
      <video
        ref={ref}
        src={src}
        controls
        playsInline
        preload="metadata"
        className={className}
        style={style}
        onLoadedData={onLoadedData}
        onError={onError}
      />
    );
  })
);

MemoizedVideo.displayName = 'MemoizedVideo';
