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
import {Pencil, Plus, Trash2} from 'lucide-react-native';

import {useAuth} from '../auth/AuthContext';
import {FluentCard, FluentCaption, FluentTitle} from '../components/fluent';
import {useI18n} from '../i18n';
import {colors, spacing} from '../theme/colors';
import type {RootStackParamList} from '../navigation/types';
import type {LanluServer} from '../storage/servers';

type Props = NativeStackScreenProps<RootStackParamList, 'ServerList'>;

export function ServerListScreen({navigation}: Props) {
  const {t} = useI18n();
  const {servers, reloadServers, selectServer, deleteServer} = useAuth();

  useFocusEffect(
    useCallback(() => {
      reloadServers().catch(error => console.warn('Failed to load servers:', error));
    }, [reloadServers]),
  );

  function confirmDelete(server: LanluServer) {
    Alert.alert(t('server.deleteTitle'), t('server.deleteMessage', {name: server.name}), [
      {text: t('common.cancel'), style: 'cancel'},
      {
        text: t('common.delete'),
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
          <FluentCaption>{t('server.choose')}</FluentCaption>
        </View>
        <TouchableOpacity
          accessibilityLabel={t('server.add')}
          accessibilityRole="button"
          onPress={() => navigation.navigate('AddServer', {})}
          style={styles.addButton}>
          <Plus color={colors.white} size={20} />
        </TouchableOpacity>
      </View>

      <FlatList
        contentContainerStyle={styles.list}
        data={servers}
        keyExtractor={item => item.id}
        ListEmptyComponent={
          <FluentCard style={styles.empty}>
            <Text style={styles.emptyTitle}>{t('server.noServers')}</Text>
            <FluentCaption>{t('server.addFirst')}</FluentCaption>
            <TouchableOpacity
              accessibilityRole="button"
              onPress={() => navigation.navigate('AddServer', {})}
              style={styles.emptyButton}>
              <Plus color={colors.white} size={18} />
              <Text style={styles.emptyButtonText}>{t('server.add')}</Text>
            </TouchableOpacity>
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
                    {t('server.lastUsed', {time: new Date(item.lastUsedAt).toLocaleString()})}
                  </Text>
                ) : null}
              </View>
              <View style={styles.serverActions}>
                <TouchableOpacity
                  accessibilityLabel={t('common.edit')}
                  accessibilityRole="button"
                  onPress={() => navigation.navigate('AddServer', {server: item})}
                  style={styles.iconAction}>
                  <Pencil color={colors.textMuted} size={18} />
                </TouchableOpacity>
                <TouchableOpacity
                  accessibilityLabel={t('common.delete')}
                  accessibilityRole="button"
                  onPress={() => confirmDelete(item)}
                  style={[styles.iconAction, styles.deleteAction]}>
                  <Trash2 color={colors.danger} size={18} />
                </TouchableOpacity>
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
  addButton: {
    alignItems: 'center',
    backgroundColor: colors.primary,
    borderRadius: 20,
    height: 40,
    justifyContent: 'center',
    width: 40,
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
    alignItems: 'center',
    backgroundColor: colors.primary,
    borderRadius: 8,
    flexDirection: 'row',
    gap: spacing.xs,
    marginTop: spacing.sm,
    paddingHorizontal: spacing.md,
    paddingVertical: 9,
  },
  emptyButtonText: {
    color: colors.white,
    fontSize: 14,
    fontWeight: '800',
  },
  serverCard: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: spacing.md,
  },
  serverMain: {
    flex: 1,
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
    alignItems: 'center',
    flexDirection: 'row',
    gap: spacing.xs,
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
});
