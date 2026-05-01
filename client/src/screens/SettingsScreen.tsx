import React from 'react';
import {Alert, StyleSheet, Text, View} from 'react-native';

import {useAuth} from '../auth/AuthContext';
import {FluentButton, FluentCard, FluentCaption, FluentTitle} from '../components/fluent';
import {useI18n} from '../i18n';
import {colors, spacing} from '../theme/colors';

export function SettingsScreen() {
  const {t} = useI18n();
  const {activeServer, user, showServerList, signOut} = useAuth();

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
    gap: spacing.sm,
    justifyContent: 'flex-end',
    marginTop: spacing.sm,
  },
});
