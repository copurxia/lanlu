import React, {useState} from 'react';
import {Alert, Modal, ScrollView, Share, StyleSheet, Text, View} from 'react-native';

import {useAuth} from '../auth/AuthContext';
import {FluentButton, FluentCard, FluentCaption, FluentTitle} from '../components/fluent';
import {useI18n} from '../i18n';
import {clearDiagnosticLog, getDiagnosticLog} from '../storage/diagnostics';
import {colors, spacing} from '../theme/colors';

export function SettingsScreen() {
  const {t} = useI18n();
  const {activeServer, user, showServerList, signOut} = useAuth();
  const [diagnosticLog, setDiagnosticLog] = useState('');
  const [diagnosticsOpen, setDiagnosticsOpen] = useState(false);

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
    <View style={styles.screen}>
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
        <View style={styles.actions}>
          <FluentButton
            label={t('auth.switchServer')}
            onPress={() => {
              showServerList().catch(error =>
                console.warn('Failed to switch server:', error),
              );
            }}
          />
          <FluentButton label={t('settings.signOut')} variant="danger" onPress={confirmSignOut} />
        </View>
      </FluentCard>

      <FluentCard style={styles.section}>
        <FluentTitle>{t('settings.diagnostics')}</FluentTitle>
        <FluentCaption>{t('settings.diagnosticsDescription')}</FluentCaption>
        <View style={styles.actions}>
          <FluentButton label={t('settings.viewLogs')} onPress={openDiagnostics} />
          <FluentButton label={t('settings.shareLogs')} onPress={shareDiagnostics} />
        </View>
      </FluentCard>

      <Modal
        animationType="slide"
        onRequestClose={() => setDiagnosticsOpen(false)}
        transparent
        visible={diagnosticsOpen}>
        <View style={styles.modalBackdrop}>
          <View style={styles.logSheet}>
            <FluentTitle>{t('settings.diagnostics')}</FluentTitle>
            <ScrollView style={styles.logBox}>
              <Text selectable style={styles.logText}>{diagnosticLog}</Text>
            </ScrollView>
            <View style={styles.actions}>
              <FluentButton label={t('settings.clearLogs')} variant="danger" onPress={clearDiagnostics} />
              <FluentButton label={t('settings.shareLogs')} onPress={shareDiagnostics} />
              <FluentButton label={t('common.close')} variant="primary" onPress={() => setDiagnosticsOpen(false)} />
            </View>
          </View>
        </View>
      </Modal>
    </View>
  );
}

const styles = StyleSheet.create({
  screen: {
    backgroundColor: colors.background,
    flex: 1,
    gap: spacing.md,
    padding: spacing.lg,
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
  actions: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.sm,
    justifyContent: 'flex-end',
    marginTop: spacing.sm,
  },
  modalBackdrop: {
    backgroundColor: 'rgba(0,0,0,0.38)',
    flex: 1,
    justifyContent: 'flex-end',
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
