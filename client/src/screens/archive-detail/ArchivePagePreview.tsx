import React, {useEffect, useMemo, useState} from 'react';
import {ActivityIndicator, FlatList, StyleSheet, Text, TouchableOpacity, View} from 'react-native';
import {FileText, Film, ImageIcon, Music} from 'lucide-react-native';

import {fetchArchiveFiles} from '../../api/lanlu';
import {useTheme} from '../../theme/ThemeContext';
import {FluentCard} from '../../components/fluent';
import type {PageInfo} from '../../types/api';
import type {TFunction} from '../../i18n';

type Props = {
  archiveId: string;
  onSelectPage?: (pageIndex: number) => void;
  t: TFunction;
};

function pageTypeIcon(type: string, size: number, color: string) {
  switch (type) {
    case 'video': return <Film color={color} size={size} />;
    case 'audio': return <Music color={color} size={size} />;
    case 'html': return <FileText color={color} size={size} />;
    default: return <ImageIcon color={color} size={size} />;
  }
}

export function ArchivePagePreview({archiveId, onSelectPage, t}: Props) {
  const {colors} = useTheme();
  const [pages, setPages] = useState<PageInfo[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchArchiveFiles(archiveId)
      .then(setPages)
      .catch(() => setPages([]))
      .finally(() => setLoading(false));
  }, [archiveId]);

  const styles = useMemo(() => createStyles(colors), [colors]);

  if (loading) {
    return (
      <View style={styles.section}>
        <Text style={styles.title}>{t('archive.pagePreview')}</Text>
        <FluentCard style={styles.card}>
          <ActivityIndicator color={colors.primary} />
        </FluentCard>
      </View>
    );
  }

  if (pages.length === 0) return null;

  return (
    <View style={styles.section}>
      <Text style={styles.title}>
        {t('archive.pagePreview')} ({pages.length})
      </Text>
      <FlatList
        data={pages}
        horizontal
        showsHorizontalScrollIndicator={false}
        keyExtractor={(_, idx) => String(idx)}
        contentContainerStyle={styles.listContent}
        renderItem={({item, index}) => (
          <TouchableOpacity
            style={[styles.thumb, {backgroundColor: colors.surface, borderColor: colors.border}]}
            activeOpacity={0.7}
            onPress={() => onSelectPage?.(index)}>
            {pageTypeIcon(item.type || 'image', 24, colors.textMuted)}
            <Text style={styles.thumbLabel} numberOfLines={1}>
              {item.title || `${index + 1}`}
            </Text>
          </TouchableOpacity>
        )}
      />
    </View>
  );
}

function createStyles(colors: any) {
  return StyleSheet.create({
    section: {marginTop: 20},
    title: {color: colors.text, fontSize: 15, fontWeight: '800', marginBottom: 8},
    card: {padding: 20, alignItems: 'center'},
    listContent: {gap: 10, paddingRight: 16},
    thumb: {
      width: 80, aspectRatio: 0.72, borderRadius: 6, borderWidth: StyleSheet.hairlineWidth,
      alignItems: 'center', justifyContent: 'center', gap: 6,
    },
    thumbLabel: {color: colors.textMuted, fontSize: 10, textAlign: 'center', paddingHorizontal: 4},
  });
}
