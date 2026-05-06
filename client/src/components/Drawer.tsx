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
import {Gesture, GestureDetector} from 'react-native-gesture-handler';
import Animated, {
  runOnJS,
  useAnimatedStyle,
  useSharedValue,
  withSpring,
  withTiming,
} from 'react-native-reanimated';
import {useSafeAreaInsets} from 'react-native-safe-area-context';

type DrawerSide = 'bottom' | 'right';

type DrawerProps = {
  open: boolean;
  onClose: () => void;
  children: React.ReactNode;
  side?: DrawerSide;
  showHandle?: boolean;
  enablePanDownToClose?: boolean;
  maxHeight?: DimensionValue;
  style?: StyleProp<ViewStyle>;
};

const SPRING_IN = {damping: 22, stiffness: 220, mass: 1};
const SPRING_OUT = {damping: 20, stiffness: 200, mass: 0.9};

export function Drawer({
  open,
  onClose,
  children,
  side = 'bottom',
  showHandle = true,
  enablePanDownToClose = true,
  maxHeight = '82%',
  style,
}: DrawerProps) {
  const insets = useSafeAreaInsets();
  const [visible, setVisible] = useState(false);
  const {width: screenWidth, height: screenHeight} = useWindowDimensions();
  const isBottom = side === 'bottom';

  const backdropOpacity = useSharedValue(0);
  const translate = useSharedValue(isBottom ? screenHeight : screenWidth);
  const isClosing = useSharedValue(false);
  const onCloseRef = useRef(onClose);
  onCloseRef.current = onClose;

  const animateIn = useCallback(() => {
    'worklet';
    isClosing.value = false;
    backdropOpacity.value = withTiming(1, {duration: 300});
    translate.value = withSpring(0, SPRING_IN);
  }, [backdropOpacity, isClosing, translate]);

  const animateOut = useCallback(() => {
    'worklet';
    if (isClosing.value) return;
    isClosing.value = true;
    backdropOpacity.value = withTiming(0, {duration: 250});
    translate.value = withSpring(
      isBottom ? screenHeight : screenWidth,
      SPRING_OUT,
      (finished) => {
        if (finished) {
          runOnJS(setVisible)(false);
          runOnJS(onCloseRef.current)();
        }
      },
    );
  }, [isBottom, screenHeight, screenWidth, backdropOpacity, isClosing, translate]);

  useEffect(() => {
    if (open) {
      setVisible(true);
      animateIn();
    } else if (visible) {
      animateOut();
    }
  }, [open, animateIn, animateOut, visible]);

  const panGesture = useMemo(() => {
    if (!enablePanDownToClose || !isBottom) {
      return Gesture.Pan().enabled(false);
    }
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
          translate.value = withSpring(0, SPRING_IN);
          backdropOpacity.value = withTiming(1, {duration: 200});
        }
      });
  }, [enablePanDownToClose, isBottom, screenHeight, animateOut, backdropOpacity, translate]);

  const backdropAnimatedStyle = useAnimatedStyle(() => ({
    opacity: backdropOpacity.value,
  }));

  const sheetAnimatedStyle = useAnimatedStyle(() => {
    if (isBottom) {
      return {transform: [{translateY: translate.value}]};
    }
    return {transform: [{translateX: translate.value}]};
  });

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
        backdrop: {
          ...StyleSheet.absoluteFill,
          backgroundColor: 'rgba(0,0,0,0.38)',
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
      isBottom ? staticStyles.sheet : staticStyles.sheetRight,
      isBottom
        ? {paddingBottom: Math.max(insets.bottom, 16)}
        : {paddingTop: Math.max(insets.top, 16)},
      style,
    ],
    [isBottom, staticStyles, insets, style],
  );

  if (!visible) return null;

  return (
    <Modal
      animationType="none"
      onRequestClose={animateOut}
      statusBarTranslucent
      transparent
      visible={visible}>
      <View style={[staticStyles.root, isBottom ? staticStyles.rootBottom : staticStyles.rootRight]}>
        <Animated.View style={[staticStyles.backdrop, backdropAnimatedStyle]}>
          <Pressable
            style={StyleSheet.absoluteFill}
            onPress={animateOut}
          />
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
