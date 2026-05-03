import React, {useMemo} from 'react';
import {ActivityIndicator, FlatList, ListRenderItemInfo, StyleSheet, Text, View} from 'react-native';

import {useTheme} from '../../theme/ThemeContext';
import type {TFunction} from '../../i18n';
import type {Archive} from '../../types/api';

type Props = {
  related: Archive[];
  loading: boolean;
  t: TFunction;
  keyExtractor: (item: Archive) => string;
  renderItem: (item: Archive) => React.JSX.Element;
};

export function ArchiveRelated({related, loading, t, keyExtractor, renderItem}: Props) {
  const {colors} = useTheme();
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

  if (!loading && related.length === 0) return null;

  return (
    <View style={styles.section}>
      <Text style={styles.sectionTitle}>{t('archive.relatedTitle')}</Text>
      <Text style={styles.sectionSubtitle}>{t('archive.relatedDescription')}</Text>

      {loading ? (
        <ActivityIndicator
          color={colors.primary}
          size="small"
          style={styles.loading}
        />
      ) : related.length > 0 ? (
        <FlatList
          data={related}
          keyExtractor={keyExtractor}
          horizontal
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.list}
          renderItem={({item}: ListRenderItemInfo<Archive>) => renderItem(item)}
        />
      ) : null}
    </View>
  );
}
