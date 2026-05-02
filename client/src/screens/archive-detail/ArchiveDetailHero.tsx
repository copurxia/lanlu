import React, {useMemo} from 'react';
import {StyleSheet, Text, View} from 'react-native';
import FastImage, {type Source as FastImageSource} from '@d11/react-native-fast-image';

import {colors} from '../../theme/colors';
import type {TFunction} from '../../i18n';
import type {ArchiveMetadata} from '../../types/api';

type TvMetaSummary = {
  season?: string;
  episode?: string;
  status?: string;
  year?: string;
};

function parseTvMetaSummary(tags?: string[]): TvMetaSummary {
  if (!tags?.length) return {};
  const result: TvMetaSummary = {};
  for (const tag of tags) {
    const idx = tag.indexOf(':');
    if (idx <= 0) continue;
    const ns = tag.slice(0, idx).trim().toLowerCase();
    const value = tag.slice(idx + 1).trim();
    if (ns === 'source') continue;
    if (ns === 'season') result.season = value;
    else if (ns === 'episode') result.episode = value;
    else if (ns === 'status') result.status = value;
    else if (ns === 'year' || ns === 'release') result.year = value;
  }
  return result;
}

type Props = {
  metadata: ArchiveMetadata;
  cover: FastImageSource | null;
  backdrop: FastImageSource | null;
  t: TFunction;
};

export function ArchiveDetailHero({metadata, cover, backdrop, t}: Props) {
  const pagecount = Number(metadata.pagecount || 0);
  const progress = Number(metadata.progress || 0);
  const progressPercent =
    pagecount > 0 && progress > 0
      ? Math.max(0, Math.min(100, Math.round((progress / pagecount) * 100)))
      : 0;
  const tvMetaSummary = useMemo(() => parseTvMetaSummary(metadata.tags), [metadata.tags]);
  const isTvArchive = Boolean(tvMetaSummary.season || tvMetaSummary.episode);

  return (
    <View>
      {backdrop ? (
        <View style={styles.backdropContainer} pointerEvents="none">
          <FastImage
            source={{...backdrop, priority: FastImage.priority.low}}
            resizeMode={FastImage.resizeMode.cover}
            style={styles.backdrop}
          />
          <View style={styles.backdropOverlay} />
        </View>
      ) : null}

      <View style={styles.hero}>
        <View style={styles.coverFrame}>
          {cover ? (
            <FastImage
              source={cover}
              resizeMode={FastImage.resizeMode.cover}
              style={styles.cover}
            />
          ) : (
            <View style={styles.coverPlaceholder}>
              <Text style={styles.coverPlaceholderText}>{t('common.noCover')}</Text>
            </View>
          )}
        </View>
        <View style={styles.heroBody}>
          <View style={styles.badgeRow}>
            <View style={styles.badge}>
              <Text style={styles.badgeText}>{t('archive.archiveLabel')}</Text>
            </View>
            {tvMetaSummary.season ? (
              <View style={styles.badgeSecondary}>
                <Text style={styles.badgeSecondaryText}>
                  S{tvMetaSummary.season.padStart(2, '0')}
                </Text>
              </View>
            ) : null}
            {tvMetaSummary.status ? (
              <View style={styles.badgeOutline}>
                <Text style={styles.badgeOutlineText}>{tvMetaSummary.status}</Text>
              </View>
            ) : null}
            {tvMetaSummary.year ? (
              <View style={styles.badgeOutline}>
                <Text style={styles.badgeOutlineText}>{tvMetaSummary.year}</Text>
              </View>
            ) : null}
          </View>

          <Text style={styles.title} numberOfLines={3}>
            {metadata.title || metadata.filename || metadata.arcid}
          </Text>

          <View style={styles.stats}>
            <Text style={styles.statText}>
              {isTvArchive
                ? `${t('archive.episodeCount')} ${pagecount}`
                : `${t('archive.pageCount')} ${pagecount}`}
            </Text>
            {metadata.release_at ? (
              <>
                <Text style={styles.statDot}>•</Text>
                <Text style={styles.statText} numberOfLines={1}>
                  {t('archive.releaseAt', {date: metadata.release_at})}
                </Text>
              </>
            ) : null}
            {metadata.updated_at ? (
              <>
                <Text style={styles.statDot}>•</Text>
                <Text style={styles.statText} numberOfLines={1}>
                  {t('archive.updatedAt', {date: metadata.updated_at})}
                </Text>
              </>
            ) : null}
            {progressPercent > 0 ? (
              <>
                <Text style={styles.statDot}>•</Text>
                <Text style={styles.statText}>
                  {t('archive.progressPercent', {percent: progressPercent})}
                </Text>
              </>
            ) : null}
          </View>

          {progressPercent > 0 ? (
            <View style={styles.progressBar}>
              <View style={[styles.progressFill, {width: `${progressPercent}%`}]} />
            </View>
          ) : null}
        </View>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  backdropContainer: {
    height: 200,
    overflow: 'hidden',
    position: 'absolute',
    left: 0,
    right: 0,
    top: 0,
  },
  backdrop: {
    height: '100%',
    width: '100%',
  },
  backdropOverlay: {
    ...StyleSheet.absoluteFill,
    backgroundColor: 'rgba(0,0,0,0.55)',
  },
  hero: {
    flexDirection: 'row',
    gap: 16,
  },
  coverFrame: {
    aspectRatio: 0.72,
    backgroundColor: colors.surfaceMuted,
    borderRadius: 8,
    overflow: 'hidden',
    width: 128,
  },
  cover: {
    height: '100%',
    width: '100%',
  },
  coverPlaceholder: {
    alignItems: 'center',
    flex: 1,
    justifyContent: 'center',
  },
  coverPlaceholderText: {
    color: colors.textMuted,
  },
  heroBody: {
    flex: 1,
    gap: 6,
    justifyContent: 'center',
  },
  badgeRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 6,
  },
  badge: {
    backgroundColor: colors.primary,
    borderRadius: 4,
    paddingHorizontal: 8,
    paddingVertical: 3,
  },
  badgeText: {
    color: colors.white,
    fontSize: 11,
    fontWeight: '700',
  },
  badgeSecondary: {
    backgroundColor: colors.primaryMuted,
    borderRadius: 4,
    paddingHorizontal: 8,
    paddingVertical: 3,
  },
  badgeSecondaryText: {
    color: colors.primary,
    fontSize: 11,
    fontWeight: '700',
  },
  badgeOutline: {
    borderColor: colors.borderStrong,
    borderRadius: 4,
    borderWidth: 1,
    paddingHorizontal: 8,
    paddingVertical: 3,
  },
  badgeOutlineText: {
    color: colors.textMuted,
    fontSize: 11,
    fontWeight: '600',
  },
  title: {
    color: colors.text,
    fontSize: 20,
    fontWeight: '800',
    lineHeight: 26,
  },
  stats: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 4,
  },
  statText: {
    color: colors.textMuted,
    fontSize: 12,
  },
  statDot: {
    color: colors.textMuted,
    fontSize: 12,
    opacity: 0.5,
  },
  progressBar: {
    backgroundColor: colors.border,
    borderRadius: 4,
    height: 6,
    overflow: 'hidden',
    width: '100%',
  },
  progressFill: {
    backgroundColor: colors.primary,
    borderRadius: 4,
    height: '100%',
  },
});
