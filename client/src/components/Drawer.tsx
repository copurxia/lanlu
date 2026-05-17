import React, {useCallback, useEffect, useMemo, useRef, useState} from 'react';
import {
  type DimensionValue,
  Modal,
  Pressable,
  StyleProp,
  StyleSheet,
  View,
  ViewStyle,
  useWindowDimensions,
} from 'react-native';
import {BlurView} from '@sbaiahmed1/react-native-blur';
import {Gesture, GestureDetector} from 'react-native-gesture-handler';
import Animated, {
  runOnJS,
  useAnimatedStyle,
  useSharedValue,
  withTiming,
} from 'react-native-reanimated';
import {useSafeAreaInsets} from 'react-native-safe-area-context';

type DrawerSide = 'bottom' | 'right' | 'left';

type DrawerProps = {
  open: boolean;
  onClose: () => void;
  children: React.ReactNode;
  side?: DrawerSide;
  showHandle?: boolean;
  enablePanDownToClose?: boolean;
  maxHeight?: DimensionValue;
  backdropColor?: string;
  blurType?: 'dark' | 'light' | 'xlight' | 'prominent' | 'regular' | 'extraDark';
  style?: StyleProp<ViewStyle>;
};

export function Drawer({
  open,
  onClose,
  children,
  side = 'bottom',
  showHandle = true,
  enablePanDownToClose = true,
  maxHeight = '82%',
  backdropColor = 'rgba(0,0,0,0.38)',
  blurType = 'regular',
  style,
}: DrawerProps) {
  const insets = useSafeAreaInsets();
  const [visible, setVisible] = useState(false);
  const {width: screenWidth, height: screenHeight} = useWindowDimensions();
  const isBottom = side === 'bottom';
  const isLeft = side === 'left';

  const backdropOpacity = useSharedValue(0);
  const translate = useSharedValue(isBottom ? screenHeight : isLeft ? -screenWidth : screenWidth);
  const isClosing = useSharedValue(false);
  const onCloseRef = useRef(onClose);
  onCloseRef.current = onClose;

  const animateIn = useCallback(() => {
    'worklet';
    isClosing.value = false;
    backdropOpacity.value = withTiming(1, {duration: 300});
    translate.value = withTiming(0, {duration: 300});
  }, [backdropOpacity, isClosing, translate]);

  const animateOut = useCallback(() => {
    'worklet';
    if (isClosing.value) return;
    isClosing.value = true;
    backdropOpacity.value = withTiming(0, {duration: 250});
    const target = isBottom ? screenHeight : isLeft ? -screenWidth : screenWidth;
    translate.value = withTiming(
      target,
      {duration: 250},
      (finished) => {
        if (finished) {
          runOnJS(setVisible)(false);
          runOnJS(onCloseRef.current)();
        }
      },
    );
  }, [isBottom, isLeft, screenHeight, screenWidth, backdropOpacity, isClosing, translate]);

  useEffect(() => {
    if (open) {
      setVisible(true);
      animateIn();
    } else if (visible) {
      animateOut();
    }
  }, [open, animateIn, animateOut, visible]);

  const panGesture = useMemo(() => {
    if (!enablePanDownToClose) {
      return Gesture.Pan().enabled(false);
    }
    if (isBottom) {
      return Gesture.Pan()
        .onUpdate((event) => {
          if (event.translationY > 0) {
            translate.value = event.translationY;
            backdropOpacity.value = 1 - (event.translationY / screenHeight) * 0.6;
          }
        })
        .onEnd((event) => {
          if (event.translationY > screenHeight * 0.25 || event.velocityY > 800) {
            runOnJS(animateOut)();
          } else {
            translate.value = withTiming(0, {duration: 200});
            backdropOpacity.value = withTiming(1, {duration: 200});
          }
        });
    }
    if (isLeft) {
      return Gesture.Pan()
        .onUpdate((event) => {
          if (event.translationX > 0) {
            translate.value = -screenWidth + event.translationX;
            backdropOpacity.value = 1 - (event.translationX / screenWidth) * 0.6;
          }
        })
        .onEnd((event) => {
          if (event.translationX > screenWidth * 0.25 || event.velocityX > 800) {
            runOnJS(animateOut)();
          } else {
            translate.value = withTiming(0, {duration: 200});
            backdropOpacity.value = withTiming(1, {duration: 200});
          }
        });
    }
    return Gesture.Pan()
      .onUpdate((event) => {
        if (event.translationX < 0) {
          translate.value = screenWidth + event.translationX;
          backdropOpacity.value = 1 - (-event.translationX / screenWidth) * 0.6;
        }
      })
      .onEnd((event) => {
        if (event.translationX < -screenWidth * 0.25 || event.velocityX < -800) {
          runOnJS(animateOut)();
        } else {
          translate.value = withTiming(0, {duration: 200});
          backdropOpacity.value = withTiming(1, {duration: 200});
        }
      });
  }, [enablePanDownToClose, isBottom, isLeft, screenHeight, screenWidth, animateOut, backdropOpacity, translate]);

  const backdropAnimatedStyle = useAnimatedStyle(() => ({
    opacity: backdropOpacity.value,
    backgroundColor: backdropColor,
  }));

  const sheetAnimatedStyle = useAnimatedStyle(() => {
    if (isBottom) {
      return {transform: [{translateY: translate.value}]};
    }
    return {transform: [{translateX: translate.value}]};
  }, [isBottom]);

  const staticStyles = useMemo(
    () =>
      StyleSheet.create({
        root: {
          flex: 1,
        },
        rootBottom: {
          justifyContent: 'flex-end',
        },
        rootRight: {
          flexDirection: 'row',
          justifyContent: 'flex-end',
        },
        rootLeft: {
          flexDirection: 'row',
          justifyContent: 'flex-start',
        },
        backdrop: {
          ...StyleSheet.absoluteFill,
        },
        sheet: {
          backgroundColor: 'transparent',
          borderTopLeftRadius: 14,
          borderTopRightRadius: 14,
          maxHeight,
          overflow: 'hidden',
        },
        sheetRight: {
          backgroundColor: 'transparent',
          borderTopLeftRadius: 0,
          borderTopRightRadius: 0,
          height: '100%',
          maxHeight: '100%',
          width: 260,
        },
        sheetLeft: {
          backgroundColor: 'transparent',
          borderTopLeftRadius: 0,
          borderTopRightRadius: 0,
          height: '100%',
          maxHeight: '100%',
          width: 260,
        },
        handle: {
          alignSelf: 'center',
          backgroundColor: 'rgba(128,128,128,0.35)',
          borderRadius: 999,
          height: 4,
          marginBottom: 14,
          width: 44,
        },
      }),
    [maxHeight],
  );

  const sheetContainerStyle = useMemo(
    () => [
      isBottom ? staticStyles.sheet : isLeft ? staticStyles.sheetLeft : staticStyles.sheetRight,
      isBottom
        ? {paddingBottom: Math.max(insets.bottom, 16)}
        : {paddingTop: Math.max(insets.top, 16)},
      style,
    ],
    [isBottom, isLeft, staticStyles, insets, style],
  );

  if (!visible) return null;

  return (
    <Modal
      animationType="none"
      onRequestClose={animateOut}
      statusBarTranslucent
      transparent
      visible={visible}>
      <View style={[staticStyles.root, isBottom ? staticStyles.rootBottom : isLeft ? staticStyles.rootLeft : staticStyles.rootRight]}>
        <Animated.View style={[staticStyles.backdrop, backdropAnimatedStyle]}>
          <BlurView blurType={blurType} blurAmount={12} reducedTransparencyFallbackColor={backdropColor} style={StyleSheet.absoluteFill}>
            <Pressable
              style={StyleSheet.absoluteFill}
              onPress={animateOut}
            />
          </BlurView>
        </Animated.View>
        <GestureDetector gesture={panGesture}>
          <Animated.View style={[sheetContainerStyle, sheetAnimatedStyle]}>
            {isBottom && showHandle && <View style={staticStyles.handle} />}
            {children}
          </Animated.View>
        </GestureDetector>
      </View>
    </Modal>
  );
}
