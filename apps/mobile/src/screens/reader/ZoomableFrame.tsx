import React, {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from 'react';
import { StyleProp, StyleSheet, View, ViewStyle } from 'react-native';
import { Gesture, GestureDetector } from 'react-native-gesture-handler';
import Animated, {
  cancelAnimation,
  runOnJS,
  useAnimatedStyle,
  useSharedValue,
  withTiming,
} from 'react-native-reanimated';

import {
  clampScale,
  clampTranslation,
  translationForPinch,
  translationForZoomAt,
} from './zoomMath';

type Props = {
  children: React.ReactNode;
  width: number;
  height: number;
  /** Only the active page may stay zoomed; leaving it resets the transform. */
  active?: boolean;
  resetToken?: number;
  maxScale?: number;
  doubleTapEnabled?: boolean;
  pinchEnabled?: boolean;
  onTap?: (x: number, y: number) => void;
  onZoomChange?: (zoomed: boolean) => void;
  style?: StyleProp<ViewStyle>;
};

/**
 * Pinch / double-tap / drag zoom viewport shared by the paged and webtoon
 * readers. The parent decides whether the surrounding list may scroll.
 */
export function ZoomableFrame({
  children,
  width,
  height,
  active = true,
  resetToken,
  maxScale = 5,
  doubleTapEnabled = true,
  pinchEnabled = true,
  onTap,
  onZoomChange,
  style,
}: Props) {
  const scale = useSharedValue(1);
  const translateX = useSharedValue(0);
  const translateY = useSharedValue(0);
  const pinchStartScale = useSharedValue(1);
  const pinchStartX = useSharedValue(0);
  const pinchStartY = useSharedValue(0);
  const panStartX = useSharedValue(0);
  const panStartY = useSharedValue(0);
  const [zoomed, setZoomed] = useState(false);
  const zoomedRef = useRef(false);
  const zoomChangeRef = useRef(onZoomChange);
  const tapRef = useRef(onTap);

  useEffect(() => {
    zoomChangeRef.current = onZoomChange;
  }, [onZoomChange]);

  useEffect(() => {
    tapRef.current = onTap;
  }, [onTap]);

  const updateZoomState = useCallback((next: boolean) => {
    if (zoomedRef.current === next) return;
    zoomedRef.current = next;
    setZoomed(next);
    zoomChangeRef.current?.(next);
  }, []);

  const resetZoom = useCallback(
    (animated: boolean) => {
      cancelAnimation(scale);
      cancelAnimation(translateX);
      cancelAnimation(translateY);
      if (animated) {
        scale.value = withTiming(1, { duration: 180 });
        translateX.value = withTiming(0, { duration: 180 });
        translateY.value = withTiming(0, { duration: 180 });
      } else {
        scale.value = 1;
        translateX.value = 0;
        translateY.value = 0;
      }
      updateZoomState(false);
    },
    [scale, translateX, translateY, updateZoomState],
  );

  useEffect(() => {
    if (resetToken !== undefined) {
      resetZoom(false);
    }
  }, [resetToken, resetZoom]);

  useEffect(() => {
    if (!active) {
      resetZoom(false);
    }
  }, [active, resetZoom]);

  const dispatchTap = useCallback((x: number, y: number) => {
    tapRef.current?.(x, y);
  }, []);

  const gesture = useMemo(() => {
    const singleTap = Gesture.Tap()
      .maxDuration(240)
      .onEnd((event, success) => {
        if (success) {
          runOnJS(dispatchTap)(event.absoluteX, event.absoluteY);
        }
      });

    const doubleTap = Gesture.Tap()
      .numberOfTaps(2)
      .maxDelay(260)
      .onEnd((event, success) => {
        if (!success) return;
        if (scale.value > 1.001) {
          scale.value = withTiming(1, { duration: 180 });
          translateX.value = withTiming(0, { duration: 180 });
          translateY.value = withTiming(0, { duration: 180 });
          runOnJS(updateZoomState)(false);
          return;
        }
        const target = Math.min(2, maxScale);
        const next = translationForZoomAt(
          target,
          event.x,
          event.y,
          width,
          height,
        );
        scale.value = withTiming(target, { duration: 220 });
        translateX.value = withTiming(next.x, { duration: 220 });
        translateY.value = withTiming(next.y, { duration: 220 });
        runOnJS(updateZoomState)(true);
      });

    const taps = doubleTapEnabled
      ? Gesture.Exclusive(doubleTap, singleTap)
      : singleTap;

    const pinch = Gesture.Pinch()
      .enabled(pinchEnabled)
      .onStart(() => {
        pinchStartScale.value = scale.value;
        pinchStartX.value = translateX.value;
        pinchStartY.value = translateY.value;
      })
      .onUpdate(event => {
        const nextScale = clampScale(
          pinchStartScale.value * event.scale,
          1,
          maxScale,
        );
        const next = translationForPinch(
          pinchStartScale.value,
          nextScale,
          pinchStartX.value,
          pinchStartY.value,
          event.focalX,
          event.focalY,
          width,
          height,
        );
        scale.value = nextScale;
        translateX.value = next.x;
        translateY.value = next.y;
      })
      .onEnd(() => {
        if (scale.value < 1.02) {
          cancelAnimation(scale);
          cancelAnimation(translateX);
          cancelAnimation(translateY);
          scale.value = withTiming(1, { duration: 160 });
          translateX.value = withTiming(0, { duration: 160 });
          translateY.value = withTiming(0, { duration: 160 });
          runOnJS(updateZoomState)(false);
        } else {
          runOnJS(updateZoomState)(true);
        }
      });

    const pan = Gesture.Pan()
      .enabled(active && zoomed)
      .minDistance(4)
      .onStart(() => {
        panStartX.value = translateX.value;
        panStartY.value = translateY.value;
      })
      .onUpdate(event => {
        const next = clampTranslation(
          panStartX.value + event.translationX,
          panStartY.value + event.translationY,
          scale.value,
          width,
          height,
        );
        translateX.value = next.x;
        translateY.value = next.y;
      });

    return Gesture.Simultaneous(pinch, pan, taps);
  }, [
    active,
    dispatchTap,
    doubleTapEnabled,
    height,
    maxScale,
    pinchEnabled,
    pinchStartScale,
    pinchStartX,
    pinchStartY,
    panStartX,
    panStartY,
    scale,
    translateX,
    translateY,
    updateZoomState,
    width,
    zoomed,
  ]);

  const animatedStyle = useAnimatedStyle(() => ({
    transform: [
      { translateX: translateX.value },
      { translateY: translateY.value },
      { scale: scale.value },
    ],
  }));

  return (
    <GestureDetector gesture={gesture}>
      <View style={[styles.frame, { width, height }, style]}>
        <Animated.View style={[StyleSheet.absoluteFill, animatedStyle]}>
          {children}
        </Animated.View>
      </View>
    </GestureDetector>
  );
}

const styles = StyleSheet.create({
  frame: {
    overflow: 'hidden',
  },
});
