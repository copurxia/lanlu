import React, {useEffect, useRef, useState} from 'react';
import {StyleProp, StyleSheet, View, ViewStyle} from 'react-native';
import Animated, {
  cancelAnimation,
  Easing,
  useAnimatedStyle,
  useSharedValue,
  withTiming,
} from 'react-native-reanimated';

type Props = {
  /** Changing this key cross-fades between the old and new content. */
  identity: string;
  duration?: number;
  style?: StyleProp<ViewStyle>;
  children: React.ReactNode;
};

type Layer = {key: string; content: React.ReactNode};

/**
 * Cross-fades its children when `identity` changes. The active layer always
 * renders the live `children`, so in-place updates such as loading -> data
 * appear immediately. Only the outgoing layer is frozen as a snapshot and
 * fades out underneath for one animation.
 */
export function CrossFadeView({identity, duration = 180, style, children}: Props) {
  const opacity = useSharedValue(1);
  const [outgoing, setOutgoing] = useState<Layer | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  // Latest rendered content of the active layer, kept in a ref so the fade-out
  // can show the final frame of the view that is being replaced.
  const activeRef = useRef<Layer>({key: identity, content: children});
  const lastIdentity = useRef(identity);
  const pendingOutgoing = useRef<Layer | null>(null);

  if (lastIdentity.current !== identity) {
    // Detect the swap during render so the incoming layer starts invisible on
    // its very first paint (no flash of fully-opaque new content).
    pendingOutgoing.current = activeRef.current;
    lastIdentity.current = identity;
    activeRef.current = {key: identity, content: children};
    opacity.value = 0;
  } else {
    activeRef.current = {key: identity, content: children};
  }

  useEffect(() => {
    const previous = pendingOutgoing.current;
    pendingOutgoing.current = null;
    if (!previous) return;
    setOutgoing(previous);
    opacity.value = 0;
    opacity.value = withTiming(1, {duration, easing: Easing.out(Easing.quad)});
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(() => {
      setOutgoing(null);
      timer.current = null;
    }, duration + 30);
  }, [duration, identity, opacity]);

  useEffect(() => {
    return () => {
      if (timer.current) clearTimeout(timer.current);
      cancelAnimation(opacity);
    };
  }, [opacity]);

  const fadeStyle = useAnimatedStyle(() => ({opacity: opacity.value}));

  return (
    <View style={[styles.container, style]}>
      {outgoing ? (
        <View key={outgoing.key} pointerEvents="none" style={StyleSheet.absoluteFill}>
          {outgoing.content}
        </View>
      ) : null}
      <Animated.View style={[StyleSheet.absoluteFill, fadeStyle]}>{children}</Animated.View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    overflow: 'hidden',
  },
});
