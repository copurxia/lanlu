import React, {useState} from 'react';
import {KeyboardAvoidingView, Platform, StyleSheet, Text, TouchableOpacity, View} from 'react-native';
import type {NativeStackScreenProps} from '@react-navigation/native-stack';
import {Save, Wifi} from 'lucide-react-native';

import {testServer} from '../api/lanlu';
import {useAuth} from '../auth/AuthContext';
import {FluentCard, FluentTextField, FluentTitle} from '../components/fluent';
import {useI18n} from '../i18n';
import {colors, spacing} from '../theme/colors';
import type {RootStackParamList} from '../navigation/types';
import {normalizeServerUrl} from '../storage/servers';

type Props = NativeStackScreenProps<RootStackParamList, 'AddServer'>;

export function AddServerScreen({route, navigation}: Props) {
  const {t} = useI18n();
  const editing = route.params?.server;
  const {saveServer, selectServer} = useAuth();
  const [name, setName] = useState(editing?.name || '');
  const [baseUrl, setBaseUrl] = useState(editing?.baseUrl || '');
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');

  async function test() {
    setBusy(true);
    setError('');
    setMessage('');
    try {
      await testServer(normalizeServerUrl(baseUrl));
      setMessage(t('server.connectionSucceeded'));
    } catch (err) {
      setError(err instanceof Error ? err.message : t('server.connectionFailed'));
    } finally {
      setBusy(false);
    }
  }

  async function save() {
    const normalized = normalizeServerUrl(baseUrl);
    if (!normalized) {
      setError(t('server.urlRequired'));
      return;
    }
    setBusy(true);
    setError('');
    try {
      const server = await saveServer({
        id: editing?.id,
        name: name || normalized,
        baseUrl: normalized,
      });
      await selectServer(server);
      navigation.popToTop();
    } catch (err) {
      setError(err instanceof Error ? err.message : t('server.saveFailed'));
    } finally {
      setBusy(false);
    }
  }

  return (
    <KeyboardAvoidingView
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      style={styles.screen}>
      <FluentCard style={styles.card}>
        <FluentTitle>{editing ? t('server.edit') : t('server.add')}</FluentTitle>
        <FluentTextField label={t('server.name')} value={name} onChangeText={setName} />
        <FluentTextField
          autoCapitalize="none"
          autoCorrect={false}
          inputMode="url"
          label={t('server.url')}
          placeholder={Platform.OS === 'android' ? 'http://10.0.2.2:8082' : 'https://lanlu.example.com'}
          value={baseUrl}
          onChangeText={setBaseUrl}
        />
        {message ? <Text style={styles.message}>{message}</Text> : null}
        {error ? <Text style={styles.error}>{error}</Text> : null}
        <View style={styles.actions}>
          <TouchableOpacity
            accessibilityLabel={t('common.test')}
            accessibilityRole="button"
            activeOpacity={0.78}
            disabled={busy}
            onPress={test}
            style={[styles.secondaryButton, busy && styles.buttonDisabled]}>
            <Wifi color={colors.textMuted} size={16} />
            <Text style={styles.secondaryButtonText}>{t('common.test')}</Text>
          </TouchableOpacity>
          <TouchableOpacity
            accessibilityLabel={busy ? t('common.saving') : t('common.save')}
            accessibilityRole="button"
            activeOpacity={0.82}
            disabled={busy}
            onPress={save}
            style={[styles.primaryButton, busy && styles.buttonDisabled]}>
            <Save color={colors.white} size={16} />
            <Text style={styles.primaryButtonText}>
              {busy ? t('common.saving') : t('common.save')}
            </Text>
          </TouchableOpacity>
        </View>
      </FluentCard>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  screen: {
    backgroundColor: colors.background,
    flex: 1,
    justifyContent: 'center',
    padding: spacing.lg,
  },
  card: {
    alignSelf: 'center',
    gap: spacing.md,
    maxWidth: 460,
    width: '100%',
  },
  actions: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: spacing.sm,
    justifyContent: 'flex-end',
    marginTop: spacing.sm,
  },
  primaryButton: {
    alignItems: 'center',
    backgroundColor: colors.primary,
    borderRadius: 8,
    flexDirection: 'row',
    gap: spacing.xs,
    height: 40,
    justifyContent: 'center',
    paddingHorizontal: spacing.md,
  },
  primaryButtonText: {
    color: colors.white,
    fontSize: 14,
    fontWeight: '800',
  },
  secondaryButton: {
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderColor: colors.borderStrong,
    borderRadius: 8,
    borderWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    gap: spacing.xs,
    height: 40,
    justifyContent: 'center',
    paddingHorizontal: spacing.md,
  },
  secondaryButtonText: {
    color: colors.text,
    fontSize: 14,
    fontWeight: '800',
  },
  buttonDisabled: {
    opacity: 0.62,
  },
  message: {
    color: colors.success,
    fontSize: 13,
  },
  error: {
    color: colors.danger,
    fontSize: 13,
    lineHeight: 18,
  },
});
