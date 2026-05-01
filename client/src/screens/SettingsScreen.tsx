import React from 'react';
import {Alert, StyleSheet, Text, View} from 'react-native';

import {useAuth} from '../auth/AuthContext';
import {FluentButton, FluentCard, FluentCaption, FluentTitle} from '../components/fluent';
import {colors, spacing} from '../theme/colors';

export function SettingsScreen() {
  const {activeServer, user, showServerList, signOut} = useAuth();

  function confirmSignOut() {
    Alert.alert('Sign out', 'Clear the session for this server?', [
      {text: 'Cancel', style: 'cancel'},
      {
        text: 'Sign out',
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
        <FluentTitle>Account</FluentTitle>
        <View style={styles.row}>
          <Text style={styles.label}>User</Text>
          <Text style={styles.value}>{user?.username || 'Unknown'}</Text>
        </View>
        <View style={styles.row}>
          <Text style={styles.label}>Server</Text>
          <Text style={styles.value}>{activeServer?.name || 'Lanlu'}</Text>
          <FluentCaption>{activeServer?.baseUrl || ''}</FluentCaption>
        </View>
      </FluentCard>

      <FluentCard style={styles.section}>
        <FluentTitle>Client</FluentTitle>
        <FluentCaption>
          Switch to another saved server, or clear this server session.
        </FluentCaption>
        <View style={styles.actions}>
          <FluentButton
            label="Switch server"
            onPress={() => {
              showServerList().catch(error =>
                console.warn('Failed to switch server:', error),
              );
            }}
          />
          <FluentButton label="Sign out" variant="danger" onPress={confirmSignOut} />
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
