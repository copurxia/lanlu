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
import {colors, spacing} from '../theme/colors';

export function LoginScreen() {
  const {activeServer, signIn, showServerList} = useAuth();
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');

  async function submit() {
    if (!username.trim() || !password) {
      setError('Username and password are required.');
      return;
    }
    setSubmitting(true);
    setError('');
    try {
      await signIn({username, password});
    } catch (err) {
      setError(extractApiError(err, 'Login failed'));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <KeyboardAvoidingView
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      style={styles.screen}>
      <FluentCard style={styles.panel}>
        <FluentTitle>Sign in</FluentTitle>
        <Text style={styles.serverName}>{activeServer?.name || 'Lanlu server'}</Text>
        <Text numberOfLines={1} style={styles.serverUrl}>
          {activeServer?.baseUrl || ''}
        </Text>

        <FluentTextField
          autoCapitalize="none"
          autoCorrect={false}
          label="Username"
          onChangeText={setUsername}
          placeholder="admin"
          value={username}
        />

        <FluentTextField
          label="Password"
          onChangeText={setPassword}
          placeholder="Password"
          secureTextEntry
          value={password}
        />

        {error ? <Text style={styles.error}>{error}</Text> : null}

        <View style={styles.actions}>
          <FluentButton
            label="Switch server"
            onPress={() => {
              showServerList().catch(reason =>
                console.warn('Failed to switch server:', reason),
              );
            }}
          />
          <FluentButton
            disabled={submitting}
            label={submitting ? 'Signing in...' : 'Sign in'}
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
