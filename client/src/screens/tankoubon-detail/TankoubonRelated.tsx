import React, {useMemo} from 'react';
import {ActivityIndicator, FlatList, ListRenderItemInfo, StyleSheet, Text, View} from 'react-native';

import {ArchiveCard} from '../../components/ArchiveCard';
import {useTheme} from '../../theme/ThemeContext';
import type {TFunction} from '../../i18n';
import type {Tankoubon} from '../../types/api';

type Props = {
  related: Tankoubon[];
  loading: boolean;
  t: TFunction;
  onPress: (item: Tankoubon) => void;
};

export function TankoubonRelated({related, loading, t, onPress}: Props) {
  const {colors} = useTheme();
  if (!loading && related.length === 0) return null;

  const styles = useMemo(
    () =>
      StyleSheet.create({
        section: {
          marginTop: 24,
        },
        sectionTitle: {
          color: colors.text,
          fontSize: 15,
          fontWeight: '800',
          marginBottom: 2,
        },
        sectionSubtitle: {
          color: colors.textMuted,
          fontSize: 12,
          marginBottom: 10,
        },
        loading: {
          paddingVertical: 20,
        },
        list: {
          gap: 10,
        },
      }),
    [colors],
  );

  return (
    <View style={styles.section}>
      <Text style={styles.sectionTitle}>{t('tankoubon.relatedTitle')}</Text>
      <Text style={styles.sectionSubtitle}>{t('tankoubon.relatedDescription')}</Text>

      {loading ? (
        <ActivityIndicator
          color={colors.primary}
          size="small"
          style={styles.loading}
        />
      ) : related.length > 0 ? (
        <FlatList
          data={related}
          keyExtractor={item => item.tankoubon_id}
          horizontal
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.list}
          renderItem={({item}: ListRenderItemInfo<Tankoubon>) => (
            <ArchiveCard
              archive={item}
              variant="related"
              onOpenReader={() => onPress(item)}
              onOpenDetail={() => onPress(item)}
            />
          )}
        />
      ) : null}
    </View>
  );
}

