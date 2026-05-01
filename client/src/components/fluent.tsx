import React from 'react';
import {Button as FluentNativeButton} from '@fluentui-react-native/button';
import {Text as FluentNativeText} from '@fluentui-react-native/text';
import {
  ActivityIndicator,
  StyleSheet,
  TextInput,
  TextInputProps,
  TextStyle,
  View,
  ViewStyle,
} from 'react-native';

import {colors, radius, spacing} from '../theme/colors';

type ButtonProps = {
  label: string;
  onPress?: () => void;
  variant?: 'primary' | 'secondary' | 'danger' | 'ghost';
  disabled?: boolean;
  style?: ViewStyle;
};

export function FluentButton({
  label,
  onPress,
  variant = 'secondary',
  disabled,
  style,
}: ButtonProps) {
  return (
    <FluentNativeButton
      accessibilityLabel={label}
      disabled={disabled}
      style={[
        styles.button,
        variant === 'primary' && styles.buttonPrimary,
        variant === 'danger' && styles.buttonDanger,
        variant === 'ghost' && styles.buttonGhost,
        disabled && styles.disabled,
        style,
      ]}
      onClick={onPress}>
      <FluentNativeText
        style={[
          styles.buttonText,
          variant === 'primary' && styles.buttonTextPrimary,
          variant === 'danger' && styles.buttonTextDanger,
        ]}>
        {label}
      </FluentNativeText>
    </FluentNativeButton>
  );
}

export function FluentTextField(props: TextInputProps & {label?: string}) {
  return (
    <View style={styles.fieldWrap}>
      {props.label ? (
        <FluentNativeText style={styles.label}>{props.label}</FluentNativeText>
      ) : null}
      <TextInput
        {...props}
        placeholderTextColor={colors.textMuted}
        style={[styles.input, props.style]}
      />
    </View>
  );
}

export function FluentCard({
  children,
  style,
}: {
  children: React.ReactNode;
  style?: ViewStyle;
}) {
  return <View style={[styles.card, style]}>{children}</View>;
}

export function FluentTitle({
  children,
  style,
}: {
  children: React.ReactNode;
  style?: TextStyle;
}) {
  return <FluentNativeText style={[styles.title, style]}>{children}</FluentNativeText>;
}

export function FluentCaption({children}: {children: React.ReactNode}) {
  return <FluentNativeText style={styles.caption}>{children}</FluentNativeText>;
}

export function FluentSpinner({label}: {label?: string}) {
  return (
    <View style={styles.spinner}>
      <ActivityIndicator color={colors.primary} />
      {label ? <FluentNativeText style={styles.caption}>{label}</FluentNativeText> : null}
    </View>
  );
}

const styles = StyleSheet.create({
  button: {
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderColor: colors.borderStrong,
    borderRadius: radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    minHeight: 42,
    justifyContent: 'center',
    paddingHorizontal: spacing.lg,
  },
  buttonPrimary: {
    backgroundColor: colors.primary,
    borderColor: colors.primary,
  },
  buttonDanger: {
    borderColor: colors.danger,
  },
  buttonGhost: {
    backgroundColor: 'transparent',
    borderColor: 'transparent',
  },
  buttonText: {
    color: colors.text,
    fontSize: 15,
    fontWeight: '700',
  },
  buttonTextPrimary: {
    color: colors.white,
  },
  buttonTextDanger: {
    color: colors.danger,
  },
  disabled: {
    opacity: 0.55,
  },
  fieldWrap: {
    gap: spacing.xs,
  },
  label: {
    color: colors.text,
    fontSize: 13,
    fontWeight: '700',
  },
  input: {
    backgroundColor: colors.white,
    borderColor: colors.borderStrong,
    borderRadius: radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    color: colors.text,
    fontSize: 15,
    minHeight: 44,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
  },
  card: {
    backgroundColor: colors.surface,
    borderColor: colors.border,
    borderRadius: radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    padding: spacing.lg,
  },
  title: {
    color: colors.text,
    fontSize: 22,
    fontWeight: '800',
    letterSpacing: 0,
  },
  caption: {
    color: colors.textMuted,
    fontSize: 13,
    lineHeight: 18,
  },
  spinner: {
    alignItems: 'center',
    gap: spacing.sm,
    justifyContent: 'center',
    padding: spacing.xl,
  },
});
