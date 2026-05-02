import React from 'react';
import {ActivityIndicator, FlatList, ListRenderItemInfo, StyleSheet, Text, TouchableOpacity, View} from 'react-native';

import {colors} from '../../theme/colors';
import type {TFunction} from '../../i18n';
import type {Tankoubon} from '../../types/api';

type Props = {
  related: Tankoubon[];
  loading: boolean;
  t: TFunction;
  onPress: (item: Tankoubon) => void;
};

export function TankoubonRelated({related, loading, t, onPress}: Props) {
  if (!loading && related.length === 0) return null;

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
            <TouchableOpacity
              style={styles.card}
              onPress={() => onPress(item)}>
              <View style={styles.coverPlaceholder}>
                <Text style={styles.coverPlaceholderText}>
                  {item.title?.[0] || 'C'}
                </Text>
              </View>
              <Text style={styles.cardTitle} numberOfLines={2}>
                {item.title || item.tankoubon_id}
              </Text>
            </TouchableOpacity>
          )}
        />
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
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
  card: {
    width: 120,
  },
  coverPlaceholder: {
    aspectRatio: 0.72,
    alignItems: 'center',
    backgroundColor: colors.primaryMuted,
    borderRadius: 6,
    justifyContent: 'center',
    width: '100%',
  },
  coverPlaceholderText: {
    color: colors.primary,
    fontSize: 18,
    fontWeight: '800',
  },
  cardTitle: {
    color: colors.text,
    fontSize: 12,
    marginTop: 4,
  },
});
