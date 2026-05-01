import React, {useCallback} from 'react';
import {
  Alert,
  FlatList,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import type {NativeStackScreenProps} from '@react-navigation/native-stack';
import {useFocusEffect} from '@react-navigation/native';

import {useAuth} from '../auth/AuthContext';
import {FluentButton, FluentCard, FluentCaption, FluentTitle} from '../components/fluent';
import {colors, spacing} from '../theme/colors';
import type {RootStackParamList} from '../navigation/types';
import type {LanluServer} from '../storage/servers';

type Props = NativeStackScreenProps<RootStackParamList, 'ServerList'>;

export function ServerListScreen({navigation}: Props) {
  const {servers, reloadServers, selectServer, deleteServer} = useAuth();

  useFocusEffect(
    useCallback(() => {
      reloadServers().catch(error => console.warn('Failed to load servers:', error));
    }, [reloadServers]),
  );

  function confirmDelete(server: LanluServer) {
    Alert.alert('Delete server', `Remove ${server.name}?`, [
      {text: 'Cancel', style: 'cancel'},
      {
        text: 'Delete',
        style: 'destructive',
        onPress: () => {
          deleteServer(server.id).catch(error =>
            console.warn('Failed to delete server:', error),
          );
        },
      },
    ]);
  }

  return (
    <View style={styles.screen}>
      <View style={styles.header}>
        <View style={styles.headerText}>
          <FluentTitle>Lanlu</FluentTitle>
          <FluentCaption>Choose a server to open your library.</FluentCaption>
        </View>
        <FluentButton
          label="Add"
          variant="primary"
          onPress={() => navigation.navigate('AddServer', {})}
        />
      </View>

      <FlatList
        contentContainerStyle={styles.list}
        data={servers}
        keyExtractor={item => item.id}
        ListEmptyComponent={
          <FluentCard style={styles.empty}>
            <Text style={styles.emptyTitle}>No servers yet</Text>
            <FluentCaption>Add your first Lanlu server to continue.</FluentCaption>
            <FluentButton
              label="Add server"
              variant="primary"
              style={styles.emptyButton}
              onPress={() => navigation.navigate('AddServer', {})}
            />
          </FluentCard>
        }
        renderItem={({item}) => (
          <TouchableOpacity
            activeOpacity={0.78}
            onPress={() => {
              selectServer(item).catch(error =>
                console.warn('Failed to select server:', error),
              );
            }}>
            <FluentCard style={styles.serverCard}>
              <View style={styles.serverMain}>
                <Text style={styles.serverName}>{item.name}</Text>
                <Text numberOfLines={1} style={styles.serverUrl}>
                  {item.baseUrl}
                </Text>
                {item.lastUsedAt ? (
                  <Text style={styles.lastUsed}>
                    Last used {new Date(item.lastUsedAt).toLocaleString()}
                  </Text>
                ) : null}
              </View>
              <View style={styles.serverActions}>
                <FluentButton
                  label="Edit"
                  variant="ghost"
                  onPress={() => navigation.navigate('AddServer', {server: item})}
                />
                <FluentButton
                  label="Delete"
                  variant="ghost"
                  onPress={() => confirmDelete(item)}
                />
              </View>
            </FluentCard>
          </TouchableOpacity>
        )}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  screen: {
    backgroundColor: colors.background,
    flex: 1,
  },
  header: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: spacing.md,
    padding: spacing.lg,
  },
  headerText: {
    flex: 1,
    gap: spacing.xs,
  },
  list: {
    flexGrow: 1,
    gap: spacing.md,
    padding: spacing.lg,
    paddingTop: 0,
  },
  empty: {
    alignItems: 'flex-start',
    gap: spacing.sm,
  },
  emptyTitle: {
    color: colors.text,
    fontSize: 17,
    fontWeight: '800',
  },
  emptyButton: {
    marginTop: spacing.sm,
  },
  serverCard: {
    gap: spacing.md,
  },
  serverMain: {
    gap: spacing.xs,
  },
  serverName: {
    color: colors.text,
    fontSize: 17,
    fontWeight: '800',
  },
  serverUrl: {
    color: colors.primary,
    fontSize: 14,
  },
  lastUsed: {
    color: colors.textMuted,
    fontSize: 12,
  },
  serverActions: {
    flexDirection: 'row',
    justifyContent: 'flex-end',
  },
});
