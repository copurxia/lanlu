import React from 'react';
import {
  Modal,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import {Check} from 'lucide-react-native';
import {colors, spacing} from '../../theme/colors';
import {ModalBackdrop} from '../../components/SafeAreaSurface';

export type SelectOption = {
  value: number;
  label: string;
};

type Props = {
  open: boolean;
  title: string;
  options: SelectOption[];
  selectedValues: number[];
  multiSelect?: boolean;
  onSelect: (value: number) => void;
  onClose: () => void;
  t: (key: string, params?: Record<string, string | number>) => string;
};

export function OptionSelectSheet({
  open,
  title,
  options,
  selectedValues,
  multiSelect,
  onSelect,
  onClose,
  t,
}: Props) {
  const selectedSet = React.useMemo(() => new Set(selectedValues), [selectedValues]);

  return (
    <Modal
      animationType="fade"
      onRequestClose={onClose}
      statusBarTranslucent
      transparent
      visible={open}>
      <ModalBackdrop style={styles.backdrop}>
        <View style={styles.sheet}>
          <View style={styles.sheetHandle} />
          <Text style={styles.sheetTitle}>{title}</Text>
          <ScrollView style={styles.list}>
            {options.map(option => {
              const isSelected = selectedSet.has(option.value);
              return (
                <TouchableOpacity
                  key={`option-${option.value}`}
                  onPress={() => onSelect(option.value)}
                  style={[styles.optionRow, isSelected && styles.optionRowActive]}>
                  <View style={styles.checkbox}>
                    {isSelected && (
                      <Check color={multiSelect ? colors.primary : colors.white} size={16} />
                    )}
                  </View>
                  <Text
                    numberOfLines={2}
                    style={[styles.optionLabel, isSelected && styles.optionLabelActive]}>
                    {option.label}
                  </Text>
                </TouchableOpacity>
              );
            })}
          </ScrollView>
          <TouchableOpacity onPress={onClose} style={styles.closeButton}>
            <Text style={styles.closeButtonText}>{t('common.close')}</Text>
          </TouchableOpacity>
        </View>
      </ModalBackdrop>
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: {
    backgroundColor: 'rgba(0,0,0,0.38)',
    flex: 1,
    justifyContent: 'flex-end',
  },
  sheet: {
    backgroundColor: colors.surface,
    borderTopLeftRadius: 14,
    borderTopRightRadius: 14,
    maxHeight: '60%',
    padding: spacing.lg,
  },
  sheetHandle: {
    alignSelf: 'center',
    backgroundColor: colors.borderStrong,
    borderRadius: 999,
    height: 4,
    marginBottom: spacing.md,
    width: 44,
  },
  sheetTitle: {
    color: colors.text,
    fontSize: 18,
    fontWeight: '800',
    marginBottom: spacing.md,
  },
  list: {
    maxHeight: 320,
  },
  optionRow: {
    alignItems: 'center',
    borderColor: colors.border,
    borderRadius: 8,
    borderWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    marginBottom: 6,
    paddingHorizontal: spacing.md,
    paddingVertical: 12,
  },
  optionRowActive: {
    backgroundColor: colors.primaryMuted,
    borderColor: colors.primary,
  },
  checkbox: {
    alignItems: 'center',
    borderRadius: 12,
    height: 24,
    justifyContent: 'center',
    marginRight: 10,
    width: 24,
  },
  optionLabel: {
    color: colors.text,
    flex: 1,
    fontSize: 15,
    fontWeight: '700',
    minWidth: 0,
  },
  optionLabelActive: {
    color: colors.primary,
  },
  closeButton: {
    alignItems: 'center',
    backgroundColor: colors.primary,
    borderRadius: 8,
    marginTop: spacing.md,
    paddingVertical: 12,
  },
  closeButtonText: {
    color: colors.white,
    fontSize: 15,
    fontWeight: '800',
  },
});
