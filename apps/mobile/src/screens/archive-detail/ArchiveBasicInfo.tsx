import React, {useMemo} from 'react';
import {StyleSheet, Text, View} from 'react-native';
import {Info} from 'lucide-react-native';

import {useTheme} from '../../theme/ThemeContext';
import {FluentCard} from '../../components/fluent';
import type {TFunction} from '../../i18n';
import type {ArchiveMetadata, Archive} from '../../types/api';

type Props = {
  metadata: ArchiveMetadata;
  archive?: Archive;
  t: TFunction;
};

function formatDate(value?: string, fallback = '-'): string {
  if (!value) return fallback;
  try {
    const d = new Date(value);
    if (isNaN(d.getTime())) return fallback;
    return d.toLocaleDateString();
  } catch {
    return fallback;
  }
}

function formatLastRead(lastreadtime?: number, fallback = '-'): string {
  if (!lastreadtime || lastreadtime <= 0) return fallback;
  try {
    return new Date(lastreadtime * 1000).toLocaleDateString();
  } catch {
    return fallback;
  }
}

function formatFileSize(bytes?: number): string {
  if (bytes == null || bytes < 0) return '-';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
}

export function ArchiveBasicInfo({metadata, archive, t}: Props) {
  const {colors} = useTheme();
  const styles = useMemo(() => createStyles(colors), [colors]);

  const pagecount = Number(metadata.pagecount || archive?.pagecount || 0);
  const progress = Number(metadata.progress || archive?.progress || 0);
  const filePath = [archive?.relative_path, archive?.filename || metadata.filename]
    .filter(Boolean)
    .join('/') || '-';
  const fileSize = metadata.size ?? archive?.size;
  const fileType = (metadata.archivetype || archive?.archivetype || '').toUpperCase() || '-';
  const lastRead = archive?.lastreadtime ? formatLastRead(archive.lastreadtime, t('archive.neverRead')) : t('archive.neverRead');

  const rows = [
    {label: t('archive.fileName'), value: filePath},
    {label: t('archive.pageCount'), value: String(pagecount)},
    {label: t('archive.infoProgress'), value: `${progress}/${pagecount || 0}`},
    {label: t('archive.infoRelease'), value: formatDate(metadata.release_at, t('archive.unknown'))},
    {label: t('archive.lastRead'), value: lastRead},
    {label: t('archive.status'), value: metadata.isnew ? t('archive.statusNew') : t('archive.statusRead')},
    {label: t('archive.fileSize'), value: formatFileSize(fileSize)},
    {label: t('archive.fileType'), value: fileType},
    {label: t('archive.createdAt'), value: formatDate(metadata.created_at, t('archive.unknown'))},
    {label: t('archive.infoUpdated'), value: formatDate(metadata.updated_at, t('archive.unknown'))},
  ];

  return (
    <View style={styles.section}>
      <View style={styles.titleRow}>
        <Info size={16} color={colors.textMuted} />
        <Text style={styles.title}>{t('archive.basicInfo')}</Text>
      </View>
      <FluentCard style={styles.card}>
        {rows.map((row, i) => (
          <View key={i} style={styles.row}>
            <Text style={styles.label}>{row.label}</Text>
            <Text style={styles.value} numberOfLines={2}>{row.value}</Text>
          </View>
        ))}
      </FluentCard>
    </View>
  );
}

function createStyles(colors: any) {
  return StyleSheet.create({
    section: {marginTop: 20},
    titleRow: {flexDirection: 'row', alignItems: 'center', gap: 8, marginBottom: 8},
    title: {color: colors.text, fontSize: 15, fontWeight: '800'},
    card: {padding: 14, gap: 10},
    row: {flexDirection: 'row', justifyContent: 'space-between', gap: 12},
    label: {color: colors.textMuted, fontSize: 13, flexShrink: 0},
    value: {color: colors.text, fontSize: 13, textAlign: 'right', flex: 1},
  });
}
