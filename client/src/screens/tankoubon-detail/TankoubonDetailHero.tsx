import React from 'react';
import {StyleSheet, Text, View} from 'react-native';
import FastImage, {type Source as FastImageSource} from '@d11/react-native-fast-image';

import {colors} from '../../theme/colors';
import type {TFunction} from '../../i18n';
import type {TankoubonMetadata} from '../../types/api';

type Props = {
  tankoubon: TankoubonMetadata;
  cover: FastImageSource | null;
  backdrop: FastImageSource | null;
  t: TFunction;
};

export function TankoubonDetailHero({tankoubon, cover, backdrop, t}: Props) {
  const archiveCount = Number(tankoubon.archive_count || 0);
  const totalPages = Number(tankoubon.pagecount || 0);
  const totalProgress = Number(tankoubon.progress || 0);
  const progressPercent =
    totalPages > 0 && totalProgress > 0
      ? Math.max(0, Math.min(100, Math.round((totalProgress / totalPages) * 100)))
      : 0;

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
              source={{
                ...cover,
                cache: FastImage.cacheControl.web,
                priority: FastImage.priority.high,
              }}
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
              <Text style={styles.badgeText}>{t('tankoubon.collection')}</Text>
            </View>
          </View>

          <Text style={styles.title} numberOfLines={3}>
            {tankoubon.title || tankoubon.tankoubon_id}
          </Text>

          <View style={styles.stats}>
            <Text style={styles.statText}>
              {t('tankoubon.archiveCount')} {archiveCount}
            </Text>
            {totalPages > 0 ? (
              <>
                <Text style={styles.statDot}>•</Text>
                <Text style={styles.statText}>
                  {t('tankoubon.totalPagesLabel')} {totalPages}
                </Text>
              </>
            ) : null}
            {progressPercent > 0 ? (
              <>
                <Text style={styles.statDot}>•</Text>
                <Text style={styles.statText}>
                  {t('tankoubon.progressPercent', {percent: progressPercent})}
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
