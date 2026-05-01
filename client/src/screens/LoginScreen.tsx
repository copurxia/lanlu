import React, {useState} from 'react';
import {
  KeyboardAvoidingView,
  Platform,
  StyleSheet,
  Text,
  View,
} from 'react-native';

import {extractApiError} from '../api/client';
import {useAuth} from '../auth/AuthContext';
import {FluentButton, FluentCard, FluentTextField, FluentTitle} from '../components/fluent';
import {useI18n} from '../i18n';
import {colors, spacing} from '../theme/colors';

export function LoginScreen() {
  const {t} = useI18n();
  const {activeServer, signIn, showServerList} = useAuth();
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');

  async function submit() {
    if (!username.trim() || !password) {
      setError(t('auth.credentialsRequired'));
      return;
    }
    setSubmitting(true);
    setError('');
    try {
      await signIn({username, password});
    } catch (err) {
      setError(extractApiError(err, t('auth.loginFailed')));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <KeyboardAvoidingView
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      style={styles.screen}>
      <FluentCard style={styles.panel}>
        <FluentTitle>{t('auth.signIn')}</FluentTitle>
        <Text style={styles.serverName}>{activeServer?.name || t('auth.lanluServer')}</Text>
        <Text numberOfLines={1} style={styles.serverUrl}>
          {activeServer?.baseUrl || ''}
        </Text>

        <FluentTextField
          autoCapitalize="none"
          autoCorrect={false}
          label={t('auth.username')}
          onChangeText={setUsername}
          placeholder="admin"
          value={username}
        />

        <FluentTextField
          label={t('auth.password')}
          onChangeText={setPassword}
          placeholder="Password"
          secureTextEntry
          value={password}
        />

        {error ? <Text style={styles.error}>{error}</Text> : null}

        <View style={styles.actions}>
          <FluentButton
            label={t('auth.switchServer')}
            onPress={() => {
              showServerList().catch(reason =>
                console.warn('Failed to switch server:', reason),
              );
            }}
          />
          <FluentButton
            disabled={submitting}
            label={submitting ? t('auth.signingIn') : t('auth.signIn')}
            onPress={submit}
            variant="primary"
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
    justifyContent: 'center',
    padding: spacing.lg,
  },
  panel: {
    gap: spacing.md,
  },
  serverName: {
    color: colors.text,
    fontSize: 16,
    fontWeight: '800',
  },
  serverUrl: {
    color: colors.primary,
    fontSize: 13,
  },
  error: {
    color: colors.danger,
    fontSize: 13,
    lineHeight: 18,
    marginTop: 14,
  },
  actions: {
    flexDirection: 'row',
    gap: spacing.sm,
    justifyContent: 'flex-end',
    marginTop: spacing.sm,
  },
});
