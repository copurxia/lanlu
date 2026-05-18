import React, {useEffect, useMemo, useRef} from 'react';
import {Animated, Easing, StyleSheet, Text, View} from 'react-native';
import Svg, {Circle, G} from 'react-native-svg';

import {spacing} from '../theme/colors';
import {useTheme} from '../theme/ThemeContext';

interface CircularProgressProps {
  value?: number;
  size?: number;
  strokeWidth?: number;
  color?: string;
  trackColor?: string;
  showLabel?: boolean;
  indeterminate?: boolean;
}

export function CircularProgress({
  value = 0,
  size = 56,
  strokeWidth = 4,
  color,
  trackColor,
  showLabel = true,
  indeterminate = false,
}: CircularProgressProps) {
  const {colors} = useTheme();
  const fillColor = color ?? colors.primary;
  const baseColor = trackColor ?? colors.borderStrong;
  const labelColor = color ?? colors.text;

  const spinValue = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    if (!indeterminate) return;
    const animation = Animated.loop(
      Animated.timing(spinValue, {
        toValue: 1,
        duration: 1500,
        easing: Easing.linear,
        useNativeDriver: true,
      }),
    );
    animation.start();
    return () => animation.stop();
  }, [indeterminate, spinValue]);

  const spin = spinValue.interpolate({
    inputRange: [0, 1],
    outputRange: ['0deg', '360deg'],
  });

  const styles = useMemo(
    () =>
      StyleSheet.create({
        wrap: {
          width: size,
          height: size,
          alignItems: 'center' as const,
          justifyContent: 'center' as const,
        },
        label: {
          color: labelColor,
          fontSize: size * 0.22,
          fontWeight: '700',
          position: 'absolute' as const,
        },
      }),
    [labelColor, size],
  );

  const radius = (size - strokeWidth) / 2;
  const circumference = radius * 2 * Math.PI;
  const clampedValue = Math.max(0, Math.min(100, value));
  const offset = circumference - (clampedValue / 100) * circumference;
  const center = size / 2;

  return (
    <Animated.View style={indeterminate ? [styles.wrap, {transform: [{rotate: spin}]}] : styles.wrap}>
      <Svg width={size} height={size} viewBox={`0 0 ${size} ${size}`}>
        <G rotation={-90} originX={center} originY={center}>
          <Circle
            cx={center}
            cy={center}
            r={radius}
            stroke={baseColor}
            strokeWidth={strokeWidth}
            fill="none"
          />
          <Circle
            cx={center}
            cy={center}
            r={radius}
            stroke={fillColor}
            strokeWidth={strokeWidth}
            strokeLinecap="round"
            fill="none"
            strokeDasharray={circumference}
            strokeDashoffset={indeterminate ? circumference / 3 : offset}
          />
        </G>
      </Svg>
      {showLabel && !indeterminate && (
        <Text style={styles.label}>
          {Math.round(clampedValue)}%
        </Text>
      )}
    </Animated.View>
  );
}
