import React, {useEffect} from 'react';
import {type StyleProp, View, type ViewStyle} from 'react-native';
import Animated, {
  cancelAnimation,
  Easing,
  useAnimatedStyle,
  useSharedValue,
  withRepeat,
  withTiming,
} from 'react-native-reanimated';
import {useTheme} from '../theme/ThemeContext';

type Props = {
  width?: number | string;
  height?: number | string;
  borderRadius?: number;
  style?: StyleProp<ViewStyle>;
};

export function Skeleton({width = '100%', height = 16, borderRadius = 6, style}: Props) {
  const {colors} = useTheme();
  const opacity = useSharedValue(0.35);

  useEffect(() => {
    opacity.value = withRepeat(
      withTiming(0.75, {duration: 700, easing: Easing.inOut(Easing.ease)}),
      -1,
      true,
    );
    return () => cancelAnimation(opacity);
  }, [opacity]);

  const animatedStyle = useAnimatedStyle(() => ({
    opacity: opacity.value,
  }));

  return (
    <Animated.View
      style={[
        {
          width: width as any,
          height: height as any,
          borderRadius,
          backgroundColor: colors.border,
        },
        animatedStyle,
        style,
      ]}
    />
  );
}

export function SkeletonBlock({lines = 3, gap = 10}: {lines?: number; gap?: number}) {
  return (
    <View style={{gap}}>
      {Array.from({length: lines}).map((_, i) => (
        <Skeleton
          key={i}
          height={14}
          width={i === lines - 1 ? '70%' : '100%'}
        />
      ))}
    </View>
  );
}
