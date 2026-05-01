import React, {useState} from 'react';
import {KeyboardAvoidingView, Platform, StyleSheet, Text, View} from 'react-native';
import type {NativeStackScreenProps} from '@react-navigation/native-stack';

import {testServer} from '../api/lanlu';
import {useAuth} from '../auth/AuthContext';
import {FluentButton, FluentCard, FluentTextField, FluentTitle} from '../components/fluent';
import {colors, spacing} from '../theme/colors';
import type {RootStackParamList} from '../navigation/types';
import {normalizeServerUrl} from '../storage/servers';

type Props = NativeStackScreenProps<RootStackParamList, 'AddServer'>;

export function AddServerScreen({route, navigation}: Props) {
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
      setMessage('Connection succeeded.');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Connection failed.');
    } finally {
      setBusy(false);
    }
  }

  async function save() {
    const normalized = normalizeServerUrl(baseUrl);
    if (!normalized) {
      setError('Server URL is required.');
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
      setError(err instanceof Error ? err.message : 'Failed to save server.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <KeyboardAvoidingView
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      style={styles.screen}>
      <FluentCard style={styles.card}>
        <FluentTitle>{editing ? 'Edit server' : 'Add server'}</FluentTitle>
        <FluentTextField label="Name" value={name} onChangeText={setName} />
        <FluentTextField
          autoCapitalize="none"
          autoCorrect={false}
          inputMode="url"
          label="Server URL"
          placeholder={Platform.OS === 'android' ? 'http://10.0.2.2:8082' : 'https://lanlu.example.com'}
          value={baseUrl}
          onChangeText={setBaseUrl}
        />
        {message ? <Text style={styles.message}>{message}</Text> : null}
        {error ? <Text style={styles.error}>{error}</Text> : null}
        <View style={styles.actions}>
          <FluentButton label="Test" disabled={busy} onPress={test} />
          <FluentButton
            label={busy ? 'Saving...' : 'Save'}
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
