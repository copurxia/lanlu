import React, {useState} from 'react';
import {StyleSheet, Text, TouchableOpacity, View} from 'react-native';

import {colors} from '../../theme/colors';
import type {TFunction} from '../../i18n';

type Props = {
  description?: string;
  t: TFunction;
};

export function ArchiveDescription({description, t}: Props) {
  const [expanded, setExpanded] = useState(false);
  const content = description?.trim();

  if (!content) {
    return (
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>{t('archive.description')}</Text>
        <Text style={styles.description}>{t('archive.noDescription')}</Text>
      </View>
    );
  }

  return (
    <View style={styles.section}>
      <Text style={styles.sectionTitle}>{t('archive.description')}</Text>
      <Text style={styles.description} numberOfLines={expanded ? undefined : 4}>
        {content}
      </Text>
      <TouchableOpacity
        style={styles.toggleButton}
        onPress={() => setExpanded(!expanded)}>
        <Text style={styles.toggleText}>
          {expanded ? t('common.collapse') : t('common.expand')}
        </Text>
      </TouchableOpacity>
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
  description: {
    color: colors.text,
    fontSize: 14,
    lineHeight: 21,
  },
  toggleButton: {
    marginTop: 6,
  },
  toggleText: {
    color: colors.primary,
    fontSize: 13,
    fontWeight: '600',
  },
});
