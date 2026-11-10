import React from 'react';
import {
  Platform,
  requireNativeComponent,
  StyleProp,
  UIManager,
  View,
  ViewProps,
  ViewStyle,
} from 'react-native';

type NativeColorFilterProps = ViewProps & {
  grayscale?: boolean;
  invertColors?: boolean;
  brightness?: number;
};

function isNativeFilterAvailable(): boolean {
  if (Platform.OS !== 'android') return false;
  try {
    const manager = UIManager as typeof UIManager & {
      hasViewManagerConfig?: (name: string) => boolean;
      getViewManagerConfig?: (name: string) => unknown;
    };
    if (typeof manager.hasViewManagerConfig === 'function') {
      return manager.hasViewManagerConfig('LanluColorFilterView');
    }
    return Boolean(manager.getViewManagerConfig?.('LanluColorFilterView'));
  } catch {
    return false;
  }
}

let NativeColorFilterView: React.ComponentType<NativeColorFilterProps> | null = null;
if (isNativeFilterAvailable()) {
  try {
    NativeColorFilterView =
      requireNativeComponent<NativeColorFilterProps>('LanluColorFilterView');
  } catch {
    NativeColorFilterView = null;
  }
}

type Props = NativeColorFilterProps & {
  children?: React.ReactNode;
  style?: StyleProp<ViewStyle>;
};

/** Applies grayscale/invert/brightness to its children on Android. */
export function ColorFilteredView({ children, ...props }: Props) {
  if (!NativeColorFilterView) {
    return <View style={props.style}>{children}</View>;
  }
  return <NativeColorFilterView {...props}>{children}</NativeColorFilterView>;
}
