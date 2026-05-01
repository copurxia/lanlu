import React, {useState} from 'react';
import {KeyboardAvoidingView, Platform, StyleSheet, Text, View} from 'react-native';
import type {NativeStackScreenProps} from '@react-navigation/native-stack';

import {testServer} from '../api/lanlu';
import {useAuth} from '../auth/AuthContext';
import {FluentButton, FluentCard, FluentTextField, FluentTitle} from '../components/fluent';
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
          <FluentButton label={t('common.test')} disabled={busy} onPress={test} />
          <FluentButton
            label={busy ? t('common.saving') : t('common.save')}
            disabled={busy}
            variant="primary"
            onPress={save}
          />
        </View>
      </FluentCard>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  screen: {
    backgroundColor: colors.background,
    flex: 1,
    padding: spacing.lg,
  },
  card: {
    gap: spacing.lg,
  },
  actions: {
    flexDirection: 'row',
    gap: spacing.sm,
    justifyContent: 'flex-end',
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
