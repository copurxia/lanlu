import React from 'react';
import {
  StyleSheet,
  type StyleProp,
  type ViewStyle,
} from 'react-native';
import {useSafeAreaInsets} from 'react-native-safe-area-context';
import Animated, {type AnimatedStyle} from 'react-native-reanimated';

import {colors, spacing} from '../theme/colors';

type EdgeInsets = {
  top: number;
  right: number;
  bottom: number;
  left: number;
};

type ScreenRootProps = {
  children: React.ReactNode;
  padded?: boolean;
  style?: StyleProp<ViewStyle>;
};

type ModalBackdropProps = {
  animatedStyle?: AnimatedStyle<ViewStyle>;
  children: React.ReactNode;
  style?: StyleProp<ViewStyle>;
};

export function screenSafeAreaPadding(insets: EdgeInsets) {
  return {
    paddingTop: insets.top + spacing.lg,
    paddingRight: Math.max(insets.right, spacing.lg),
    paddingBottom: Math.max(insets.bottom, spacing.lg),
    paddingLeft: Math.max(insets.left, spacing.lg),
  };
}

export function ScreenRoot({children, padded = true, style}: ScreenRootProps) {
  const insets = useSafeAreaInsets();
  return (
    <Animated.View
      style={[
        styles.screen,
        padded && screenSafeAreaPadding(insets),
        style,
      ]}>
      {children}
    </Animated.View>
  );
}

export function ModalBackdrop({animatedStyle, children, style}: ModalBackdropProps) {
  const insets = useSafeAreaInsets();
  return (
    <Animated.View
      style={[
        styles.backdrop,
        {
          marginTop: -insets.top,
          paddingTop: insets.top,
          paddingLeft: insets.left,
          paddingRight: insets.right,
        },
        style,
        animatedStyle,
      ]}>
      {children}
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  screen: {
    backgroundColor: colors.background,
    flex: 1,
  },
  backdrop: {
    backgroundColor: 'rgba(0,0,0,0.38)',
    flex: 1,
    justifyContent: 'flex-end',
  },
});
