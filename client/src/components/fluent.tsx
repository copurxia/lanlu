import React from 'react';
import {
  ActivityIndicator,
  Pressable,
  StyleProp,
  StyleSheet,
  Text,
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
  style?: StyleProp<ViewStyle>;
};

export function FluentButton({
  label,
  onPress,
  variant = 'secondary',
  disabled,
  style,
}: ButtonProps) {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      disabled={disabled}
      style={({pressed}) => [
        styles.button,
        variant === 'primary' && styles.buttonPrimary,
        variant === 'danger' && styles.buttonDanger,
        variant === 'ghost' && styles.buttonGhost,
        pressed && !disabled && styles.buttonPressed,
        disabled && styles.disabled,
        style,
      ]}
      onPress={onPress}>
      <Text
        style={[
          styles.buttonText,
          variant === 'primary' && styles.buttonTextPrimary,
          variant === 'danger' && styles.buttonTextDanger,
        ]}>
        {label}
      </Text>
    </Pressable>
  );
}

export function FluentTextField(props: TextInputProps & {label?: string}) {
  return (
    <View style={styles.fieldWrap}>
      {props.label ? (
        <Text style={styles.label}>{props.label}</Text>
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
  style?: StyleProp<ViewStyle>;
}) {
  return <View style={[styles.card, style]}>{children}</View>;
}

export function FluentTitle({
  children,
  style,
}: {
  children: React.ReactNode;
  style?: StyleProp<TextStyle>;
}) {
  return <Text style={[styles.title, style]}>{children}</Text>;
}

export function FluentCaption({children}: {children: React.ReactNode}) {
  return <Text style={styles.caption}>{children}</Text>;
}

export function FluentSpinner({label}: {label?: string}) {
  return (
    <View style={styles.spinner}>
      <ActivityIndicator color={colors.primary} />
      {label ? <Text style={styles.caption}>{label}</Text> : null}
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
  buttonPressed: {
    opacity: 0.78,
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
