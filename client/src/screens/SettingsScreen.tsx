import React, {useState} from 'react';
import {Alert, Modal, ScrollView, Share, StyleSheet, Text, TouchableOpacity, View} from 'react-native';
import {Check, FileText, Languages, LogOut, RotateCcw, Share2, Trash2} from 'lucide-react-native';
import {useSafeAreaInsets} from 'react-native-safe-area-context';
import Animated, {
  runOnJS,
  useAnimatedStyle,
  useSharedValue,
  withTiming,
} from 'react-native-reanimated';

import {useAuth} from '../auth/AuthContext';
import {ModalBackdrop, ScreenRoot} from '../components/SafeAreaSurface';
import {FluentCard, FluentCaption, FluentTitle} from '../components/fluent';
import {useI18n} from '../i18n';
import {clearDiagnosticLog, getDiagnosticLog} from '../storage/diagnostics';
import {colors, spacing} from '../theme/colors';

export function SettingsScreen() {
  const {languagePreference, setLanguagePreference, t} = useI18n();
  const {activeServer, user, showServerList, signOut} = useAuth();
  const insets = useSafeAreaInsets();
  const [diagnosticLog, setDiagnosticLog] = useState('');
  const [diagnosticsOpen, setDiagnosticsOpen] = useState(false);
  const diagnosticsProgress = useSharedValue(0);
  const backdropStyle = useAnimatedStyle(() => ({
    opacity: diagnosticsProgress.value,
  }));
  const sheetStyle = useAnimatedStyle(() => ({
    transform: [{translateY: (1 - diagnosticsProgress.value) * 28}],
  }));

  function confirmSignOut() {
    Alert.alert(t('settings.signOutTitle'), t('settings.signOutMessage'), [
      {text: t('common.cancel'), style: 'cancel'},
      {
        text: t('settings.signOut'),
        style: 'destructive',
        onPress: () => {
          signOut().catch(error => console.warn('Failed to sign out:', error));
        },
      },
    ]);
  }

  async function openDiagnostics() {
    const log = await getDiagnosticLog();
    setDiagnosticLog(log || t('settings.diagnosticsEmpty'));
    setDiagnosticsOpen(true);
    diagnosticsProgress.value = withTiming(1, {duration: 160});
  }

  function closeDiagnostics() {
    diagnosticsProgress.value = withTiming(0, {duration: 130}, finished => {
      if (finished) {
        runOnJS(setDiagnosticsOpen)(false);
      }
    });
  }

  async function shareDiagnostics() {
    const log = await getDiagnosticLog();
    await Share.share({
      title: t('settings.diagnostics'),
      message: log || t('settings.diagnosticsEmpty'),
    });
  }

  async function clearDiagnostics() {
    await clearDiagnosticLog();
    setDiagnosticLog(t('settings.diagnosticsEmpty'));
  }

  return (
    <ScreenRoot style={styles.screen}>
      <FluentCard style={styles.section}>
        <FluentTitle>{t('settings.account')}</FluentTitle>
        <View style={styles.row}>
          <Text style={styles.label}>{t('settings.user')}</Text>
          <Text style={styles.value}>{user?.username || t('common.unknown')}</Text>
        </View>
        <View style={styles.row}>
          <Text style={styles.label}>{t('settings.server')}</Text>
          <Text style={styles.value}>{activeServer?.name || 'Lanlu'}</Text>
          <FluentCaption>{activeServer?.baseUrl || ''}</FluentCaption>
        </View>
      </FluentCard>

      <FluentCard style={styles.section}>
        <FluentTitle>{t('settings.client')}</FluentTitle>
        <FluentCaption>
          {t('settings.clientDescription')}
        </FluentCaption>
        <View style={styles.actionList}>
          <SettingsActionRow
            icon={<RotateCcw color={colors.textMuted} size={18} />}
            label={t('auth.switchServer')}
            onPress={() => {
              showServerList().catch(error =>
                console.warn('Failed to switch server:', error),
              );
            }}
          />
          <SettingsActionRow
            danger
            icon={<LogOut color={colors.danger} size={18} />}
            label={t('settings.signOut')}
            onPress={confirmSignOut}
          />
        </View>
      </FluentCard>

      <FluentCard style={styles.section}>
        <FluentTitle>{t('settings.language')}</FluentTitle>
        <FluentCaption>{t('settings.languageDescription')}</FluentCaption>
        <View style={styles.actionList}>
          <LanguageActionRow
            active={languagePreference === 'system'}
            label={t('settings.languageSystem')}
            onPress={() => setLanguagePreference('system')}
          />
          <LanguageActionRow
            active={languagePreference === 'zh'}
            label={t('settings.languageChinese')}
            onPress={() => setLanguagePreference('zh')}
          />
          <LanguageActionRow
            active={languagePreference === 'en'}
            label={t('settings.languageEnglish')}
            onPress={() => setLanguagePreference('en')}
          />
        </View>
      </FluentCard>

      <FluentCard style={styles.section}>
        <FluentTitle>{t('settings.diagnostics')}</FluentTitle>
        <FluentCaption>{t('settings.diagnosticsDescription')}</FluentCaption>
        <View style={styles.actionList}>
          <SettingsActionRow
            icon={<FileText color={colors.textMuted} size={18} />}
            label={t('settings.viewLogs')}
            onPress={openDiagnostics}
          />
          <SettingsActionRow
            icon={<Share2 color={colors.textMuted} size={18} />}
            label={t('settings.shareLogs')}
            onPress={shareDiagnostics}
          />
        </View>
      </FluentCard>

      <Modal
        animationType="fade"
        onRequestClose={closeDiagnostics}
        statusBarTranslucent
        transparent
        visible={diagnosticsOpen}>
        <ModalBackdrop animatedStyle={backdropStyle}>
          <Animated.View style={[styles.logSheet, {paddingBottom: Math.max(insets.bottom, spacing.lg)}, sheetStyle]}>
            <FluentTitle>{t('settings.diagnostics')}</FluentTitle>
            <ScrollView style={styles.logBox}>
              <Text selectable style={styles.logText}>{diagnosticLog}</Text>
            </ScrollView>
            <View style={styles.sheetActions}>
              <TouchableOpacity
                accessibilityLabel={t('settings.clearLogs')}
                accessibilityRole="button"
                onPress={clearDiagnostics}
                style={[styles.iconAction, styles.deleteAction]}>
                <Trash2 color={colors.danger} size={18} />
              </TouchableOpacity>
              <TouchableOpacity
                accessibilityLabel={t('settings.shareLogs')}
                accessibilityRole="button"
                onPress={shareDiagnostics}
                style={styles.iconAction}>
                <Share2 color={colors.textMuted} size={18} />
              </TouchableOpacity>
              <TouchableOpacity
                accessibilityRole="button"
                onPress={closeDiagnostics}
                style={styles.closePill}>
                <Text style={styles.closePillText}>{t('common.close')}</Text>
              </TouchableOpacity>
            </View>
          </Animated.View>
        </ModalBackdrop>
      </Modal>
    </ScreenRoot>
  );
}

function LanguageActionRow({
  active,
  label,
  onPress,
}: {
  active: boolean;
  label: string;
  onPress: () => void;
}) {
  return (
    <TouchableOpacity
      activeOpacity={0.78}
      accessibilityLabel={label}
      accessibilityRole="button"
      onPress={onPress}
      style={styles.actionRow}>
      <View style={styles.languageIcon}>
        <Languages color={active ? colors.primary : colors.textMuted} size={18} />
      </View>
      <Text style={[styles.actionLabel, active && styles.actionLabelActive]}>{label}</Text>
      {active ? (
        <View style={styles.checkIcon}>
          <Check color={colors.white} size={15} />
        </View>
      ) : null}
    </TouchableOpacity>
  );
}

function SettingsActionRow({
  danger,
  icon,
  label,
  onPress,
}: {
  danger?: boolean;
  icon: React.ReactNode;
  label: string;
  onPress: () => void;
}) {
  return (
    <TouchableOpacity
      activeOpacity={0.78}
      accessibilityLabel={label}
      accessibilityRole="button"
      onPress={onPress}
      style={styles.actionRow}>
      <Text style={[styles.actionLabel, danger && styles.actionLabelDanger]}>{label}</Text>
      <View style={[styles.iconAction, danger && styles.deleteAction]}>{icon}</View>
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  screen: {
    gap: spacing.md,
  },
  section: {
    gap: spacing.md,
  },
  row: {
    gap: spacing.xs,
  },
  label: {
    color: colors.textMuted,
    fontSize: 12,
    fontWeight: '700',
    textTransform: 'uppercase',
  },
  value: {
    color: colors.text,
    fontSize: 16,
    fontWeight: '800',
  },
  actionList: {
    borderColor: colors.border,
    borderRadius: 8,
    borderWidth: StyleSheet.hairlineWidth,
    overflow: 'hidden',
  },
  actionRow: {
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderBottomColor: colors.border,
    borderBottomWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    gap: spacing.md,
    minHeight: 48,
    paddingHorizontal: spacing.md,
  },
  actionLabel: {
    color: colors.text,
    flex: 1,
    fontSize: 15,
    fontWeight: '800',
  },
  actionLabelDanger: {
    color: colors.danger,
  },
  actionLabelActive: {
    color: colors.primary,
  },
  languageIcon: {
    alignItems: 'center',
    height: 36,
    justifyContent: 'center',
    width: 28,
  },
  checkIcon: {
    alignItems: 'center',
    backgroundColor: colors.primary,
    borderRadius: 13,
    height: 26,
    justifyContent: 'center',
    width: 26,
  },
  iconAction: {
    alignItems: 'center',
    backgroundColor: colors.surfaceMuted,
    borderColor: colors.border,
    borderRadius: 18,
    borderWidth: StyleSheet.hairlineWidth,
    height: 36,
    justifyContent: 'center',
    width: 36,
  },
  deleteAction: {
    backgroundColor: '#fff5f5',
  },
  sheetActions: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: spacing.sm,
    justifyContent: 'flex-end',
  },
  closePill: {
    alignItems: 'center',
    backgroundColor: colors.primary,
    borderRadius: 18,
    height: 36,
    justifyContent: 'center',
    paddingHorizontal: spacing.lg,
  },
  closePillText: {
    color: colors.white,
    fontSize: 14,
    fontWeight: '800',
  },
  logSheet: {
    backgroundColor: colors.surface,
    borderTopLeftRadius: 14,
    borderTopRightRadius: 14,
    gap: spacing.md,
    maxHeight: '82%',
    padding: spacing.lg,
  },
  logBox: {
    backgroundColor: colors.surfaceMuted,
    borderColor: colors.border,
    borderRadius: 8,
    borderWidth: StyleSheet.hairlineWidth,
    maxHeight: 420,
    padding: spacing.md,
  },
  logText: {
    color: colors.text,
    fontFamily: 'monospace',
    fontSize: 11,
    lineHeight: 16,
  },
});
