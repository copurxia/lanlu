import React, {useState} from 'react';
import {StyleSheet, Text, TouchableOpacity, View} from 'react-native';

import {colors} from '../../theme/colors';
import type {TFunction} from '../../i18n';

type Props = {
  tags?: string[];
  onTagPress?: (tag: string) => void;
  t: TFunction;
};

export function ArchiveTags({tags, onTagPress, t}: Props) {
  if (!tags?.length) return null;

  const INITIAL_VISIBLE = 12;
  const [expanded, setExpanded] = useState(false);
  const visibleTags = expanded ? tags : tags.slice(0, INITIAL_VISIBLE);
  const hasMore = tags.length > INITIAL_VISIBLE;

  return (
    <View style={styles.section}>
      <Text style={styles.sectionTitle}>{t('archive.tags')}</Text>
      <View style={styles.tags}>
        {visibleTags.map(tag => (
          <TouchableOpacity
            key={tag}
            style={styles.tag}
            onPress={() => onTagPress?.(tag)}
            disabled={!onTagPress}>
            <Text style={styles.tagText}>{tag}</Text>
          </TouchableOpacity>
        ))}
      </View>
      {hasMore && (
        <TouchableOpacity
          style={styles.toggleButton}
          onPress={() => setExpanded(!expanded)}>
          <Text style={styles.toggleText}>
            {expanded ? t('common.collapse') : t('common.expand')}
          </Text>
        </TouchableOpacity>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  section: {
    marginTop: 20,
  },
  sectionTitle: {
    color: colors.text,
    fontSize: 15,
    fontWeight: '800',
    marginBottom: 8,
  },
  tags: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  tag: {
    backgroundColor: colors.primaryMuted,
    borderRadius: 6,
    paddingHorizontal: 10,
    paddingVertical: 5,
  },
  tagText: {
    color: colors.primary,
    fontSize: 12,
    fontWeight: '700',
  },
  toggleButton: {
    marginTop: 8,
  },
  toggleText: {
    color: colors.primary,
    fontSize: 13,
    fontWeight: '600',
  },
});
