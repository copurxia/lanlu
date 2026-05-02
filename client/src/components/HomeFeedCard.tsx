import React, {useEffect, useState} from 'react';
import {
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  useWindowDimensions,
  View,
} from 'react-native';
import FastImage, {type Source as FastImageSource} from '@d11/react-native-fast-image';
import {Eye, Film, Heart} from 'lucide-react-native';

import {
  buildAuthorizedAssetImageSource,
  buildAuthorizedImageSource,
  extractApiError,
} from '../api/client';
import {
  assetPath,
  fetchArchiveFiles,
  getPageDefaultSource,
  isTankoubon,
  mediaItemTitle,
  pagePath,
  setArchiveFavorite,
} from '../api/lanlu';
import {useI18n} from '../i18n';
import {colors, spacing} from '../theme/colors';
import type {MediaItem, PageInfo} from '../types/api';
import {
  computeChannelPreviewLayout,
  DEFAULT_CHANNEL_ASPECT_RATIO,
  type ChannelPreviewLayoutItem,
} from '../utils/channelPreviewLayout';

type Props = {
  item: MediaItem;
  mode: 'tweet' | 'channel';
  onPress: () => void;
  onDetailPress?: () => void;
  onChanged?: () => void;
  onTagPress?: (tag: string) => void;
};

type PreviewItem = ChannelPreviewLayoutItem & {
  id: string;
  kind: 'image' | 'video-poster' | 'video';
  label: string;
  measurementKey: string;
  source?: FastImageSource;
};

const PREVIEW_LIMIT = 9;
const PREVIEW_SCAN_LIMIT = 24;
const previewCache = new Map<string, Promise<PreviewItem[]>>();
const resolvedPreviewCache = new Map<string, PreviewItem[]>();
const CHANNEL_AVATAR_SIZE = 40;
const CHANNEL_ARTICLE_HORIZONTAL_PADDING = spacing.xs * 2;

function parseTags(rawTags: unknown): string[] {
  if (Array.isArray(rawTags)) return rawTags.map(tag => String(tag).trim()).filter(Boolean);
  if (!rawTags) return [];
  return String(rawTags).split(',').map(tag => tag.trim()).filter(Boolean);
}

function stripNamespace(tag: string) {
  const index = tag.indexOf(':');
  return index > 0 ? tag.slice(index + 1) : tag;
}

function exactTagQuery(tag: string) {
  const trimmed = tag.trim();
  return trimmed.endsWith('$') ? trimmed : `${trimmed}$`;
}

function authorFromTags(rawTags: string, fallback: string) {
  const tag = parseTags(rawTags).find(item => item.toLowerCase().startsWith('artist:'));
  const label = tag ? stripNamespace(tag).trim() : '';
  return label || fallback;
}

function authorInitial(author: string) {
  return Array.from(author.trim())[0]?.toUpperCase() || '?';
}

function feedTags(rawTags: string) {
  return parseTags(rawTags)
    .filter(tag => tag.split(':', 1)[0]?.trim().toLowerCase() !== 'artist')
    .slice(0, 10);
}

function previewArchiveId(item: MediaItem) {
  return isTankoubon(item) ? item.children?.[0] : item.arcid;
}

function pagePrimaryKey(page: PageInfo, index: number) {
  const source = getPageDefaultSource(page);
  return String(page.id || source?.id || source?.path || page.path || `page-${index + 1}`).trim();
}

function pageDisplayMetadata(page: PageInfo) {
  const source = getPageDefaultSource(page);
  return source?.metadata || page.metadata;
}

function pageMediaType(page: PageInfo) {
  return getPageDefaultSource(page)?.type || page.type || '';
}

function metadataAspectRatio(metadata: PageInfo['metadata'] | undefined) {
  const record = metadata as Record<string, unknown> | undefined;
  const width = Number(record?.width ?? record?.naturalWidth ?? record?.w);
  const height = Number(record?.height ?? record?.naturalHeight ?? record?.h);
  return Number.isFinite(width) && Number.isFinite(height) && width > 0 && height > 0
    ? width / height
    : DEFAULT_CHANNEL_ASPECT_RATIO;
}

function pagePreviewPath(archiveId: string, page: PageInfo): {kind: PreviewItem['kind']; path?: string} | null {
  const metadata = pageDisplayMetadata(page);
  const mediaType = pageMediaType(page);
  const thumbAsset = metadata?.thumb_asset_id;
  if (thumbAsset) {
    const path = assetPath(thumbAsset);
    if (path) return {kind: mediaType === 'video' ? 'video-poster' : 'image', path};
  }

  const thumb = metadata?.thumb?.trim();
  if (thumb) return {kind: mediaType === 'video' ? 'video-poster' : 'image', path: thumb};

  if (mediaType === 'video') return {kind: 'video'};
  if (mediaType !== 'image') return null;
  const source = getPageDefaultSource(page);
  return {kind: 'image', path: source?.url || page.url || pagePath(archiveId, page)};
}

async function buildPreviewSource(path?: string): Promise<FastImageSource | undefined> {
  if (!path) return undefined;
  const assetMatch = path.match(/\/api\/assets\/(\d+)(?:$|[?#])/);
  if (assetMatch) {
    return (await buildAuthorizedAssetImageSource(Number(assetMatch[1]), {
      priority: FastImage.priority.low,
    })) || undefined;
  }
  const source = await buildAuthorizedImageSource(path);
  return {...source, cache: FastImage.cacheControl.web, priority: FastImage.priority.low};
}

function getChannelPreviewAspectRatioCacheKey(archiveId: string, pageKey: string): string {
  return `${archiveId}|${pageKey}`;
}

const channelPreviewAspectRatioCache = new Map<string, number>();

async function loadPreviewItems(archiveId: string): Promise<PreviewItem[]> {
  const cached = previewCache.get(archiveId);
  if (cached) return cached;

  const request = fetchArchiveFiles(archiveId).then(async pages => {
    const selected = pages
      .slice(0, PREVIEW_SCAN_LIMIT)
      .map((page, index) => ({page, index, preview: pagePreviewPath(archiveId, page)}))
      .filter((entry): entry is {page: PageInfo; index: number; preview: {kind: PreviewItem['kind']; path?: string}} => Boolean(entry.preview))
      .slice(0, PREVIEW_LIMIT);

    const items = await Promise.all(
      selected.map(async ({page, index, preview}) => {
        const pageKey = pagePrimaryKey(page, index);
        const measurementKey = getChannelPreviewAspectRatioCacheKey(archiveId, pageKey);
        return {
          id: `${archiveId}:${pageKey}`,
          kind: preview.kind,
          label: page.title || '',
          measurementKey,
          aspectRatio: channelPreviewAspectRatioCache.get(measurementKey) || metadataAspectRatio(pageDisplayMetadata(page)),
          source: await buildPreviewSource(preview.path),
        };
      }),
    );
    resolvedPreviewCache.set(archiveId, items);
    return items;
  });
  previewCache.set(archiveId, request);
  return request;
}

export function HomeFeedCard({item, mode, onPress, onDetailPress, onChanged, onTagPress}: Props) {
  const {t} = useI18n();
  const {width} = useWindowDimensions();
  const currentPreviewArchiveId = previewArchiveId(item);
  const [previewItems, setPreviewItems] = useState<PreviewItem[]>(() => (
    currentPreviewArchiveId ? resolvedPreviewCache.get(currentPreviewArchiveId) || [] : []
  ));
  const [loadingPreview, setLoadingPreview] = useState(() => (
    Boolean(currentPreviewArchiveId && !resolvedPreviewCache.get(currentPreviewArchiveId))
  ));
  const [favorite, setFavorite] = useState(Boolean(item.isfavorite));
  const [expanded, setExpanded] = useState(false);
  const title = mediaItemTitle(item);
  const archive = isTankoubon(item) ? null : item;
  const tags = isTankoubon(item) ? '' : item.tags || '';
  const author = authorFromTags(tags, isTankoubon(item) ? t('home.rows') : t('home.unknownArtist'));
  const tagItems = feedTags(tags);
  const pagecount = Number(item.pagecount || 0);
  const progress = Number(item.progress || 0);
  const contentMeta = isTankoubon(item)
    ? t('common.archives', {count: item.children?.length || 0})
    : pagecount > 0 && progress > 0
      ? `${Math.min(progress, pagecount)} / ${pagecount}`
      : t('common.pages', {count: pagecount || 0});
  const contentText = [title.trim(), item.description?.trim()].filter(Boolean).join('\n\n');
  const canExpand = contentText.length > 180 || contentText.includes('\n');
  const displayContent = !expanded && canExpand ? `${contentText.slice(0, 180).trimEnd()}...` : contentText;
  const previewWidth = Math.max(
    240,
    width - spacing.lg * 2 - CHANNEL_ARTICLE_HORIZONTAL_PADDING - CHANNEL_AVATAR_SIZE - spacing.sm,
  );

  useEffect(() => {
    setFavorite(Boolean(item.isfavorite));
  }, [item]);

  useEffect(() => {
    const id = currentPreviewArchiveId;
    if (!id) {
      setPreviewItems([]);
      return;
    }
    const cachedItems = resolvedPreviewCache.get(id);
    if (cachedItems) {
      setPreviewItems(cachedItems);
    }
    let cancelled = false;
    setLoadingPreview(!cachedItems);
    loadPreviewItems(id)
      .then(items => {
        if (!cancelled) setPreviewItems(items);
      })
      .catch(error => console.warn('Failed to load feed preview:', extractApiError(error)))
      .finally(() => {
        if (!cancelled) setLoadingPreview(false);
      });
    return () => {
      cancelled = true;
    };
  }, [currentPreviewArchiveId]);

  async function toggleFavorite() {
    if (!archive) return;
    const next = !favorite;
    setFavorite(next);
    try {
      await setArchiveFavorite(archive, next);
      onChanged?.();
    } catch (error) {
      setFavorite(!next);
      console.warn(extractApiError(error));
    }
  }

  function handleMeasurePreview(measurementKey: string, aspectRatio: number) {
    const normalized = Number.isFinite(aspectRatio) && aspectRatio > 0
      ? Math.max(0.45, Math.min(aspectRatio, 2.4))
      : DEFAULT_CHANNEL_ASPECT_RATIO;
    const current = channelPreviewAspectRatioCache.get(measurementKey) || DEFAULT_CHANNEL_ASPECT_RATIO;
    if (Math.abs(current - normalized) < 0.01) return;
    channelPreviewAspectRatioCache.set(measurementKey, normalized);
    resolvedPreviewCache.forEach(items => {
      for (const previewItem of items) {
        if (previewItem.measurementKey === measurementKey) {
          previewItem.aspectRatio = normalized;
        }
      }
    });
  }

  const preview = mode === 'tweet' ? (
    <TweetPreview items={previewItems} loading={loadingPreview} label={title || author} />
  ) : (
    <ChannelPreview
      items={previewItems}
      loading={loadingPreview}
      label={title || author}
      width={previewWidth}
      onMeasure={handleMeasurePreview}
    />
  );

  if (mode === 'channel') {
    return (
      <View style={styles.channelArticle}>
        <View style={styles.channelAvatar}><Text style={styles.avatarText}>{authorInitial(author)}</Text></View>
        <View style={styles.channelBubble}>
          <View style={styles.channelActionOverlay}>
            <FeedActions favorite={favorite} favoriteDisabled={!archive} onDetailPress={onDetailPress} onToggleFavorite={toggleFavorite} />
          </View>
          <TouchableOpacity activeOpacity={0.9} onPress={onPress} style={styles.channelPreview}>
            {preview}
          </TouchableOpacity>
          <View style={styles.channelBody}>
            <View style={styles.channelHeader}>
              <Text numberOfLines={1} style={styles.author}>{author}</Text>
              <Text numberOfLines={1} style={styles.meta}>{contentMeta}</Text>
            </View>
            {displayContent ? <Text style={styles.channelText}>{displayContent}</Text> : null}
            {canExpand ? (
              <TouchableOpacity onPress={() => setExpanded(value => !value)}>
                <Text style={styles.expandText}>{expanded ? t('common.collapse') : t('common.expand')}</Text>
              </TouchableOpacity>
            ) : null}
            {renderTags(tagItems, onTagPress)}
          </View>
        </View>
      </View>
    );
  }

  return (
    <View style={[styles.card, styles.tweetCard]}>
      <View style={styles.tweetRow}>
        <View style={styles.avatar}><Text style={styles.avatarText}>{authorInitial(author)}</Text></View>
        <View style={styles.tweetContent}>
          <View style={styles.tweetHeader}>
            <View style={styles.headerText}>
              <Text numberOfLines={1} style={styles.author}>{author}</Text>
              <Text numberOfLines={1} style={styles.meta}>{contentMeta}</Text>
            </View>
            <FeedActions favorite={favorite} favoriteDisabled={!archive} onDetailPress={onDetailPress} onToggleFavorite={toggleFavorite} />
          </View>
          {displayContent ? <Text style={styles.tweetText}>{displayContent}</Text> : null}
          {canExpand ? (
            <TouchableOpacity onPress={() => setExpanded(value => !value)}>
              <Text style={styles.expandText}>{expanded ? t('common.collapse') : t('common.expand')}</Text>
            </TouchableOpacity>
          ) : null}
          {renderTags(tagItems, onTagPress)}
          <TouchableOpacity activeOpacity={0.86} onPress={onPress} style={styles.tweetPreview}>
            {preview}
            <View style={styles.previewFooter}>
              <View style={styles.previewText}>
                <Text numberOfLines={1} style={styles.previewTitle}>{title || author}</Text>
                <Text numberOfLines={1} style={styles.meta}>{contentMeta}</Text>
              </View>
              <Text style={styles.previewAction}>{t('archive.start')}</Text>
            </View>
          </TouchableOpacity>
        </View>
      </View>
    </View>
  );
}

function FeedActions({
  favorite,
  favoriteDisabled,
  onDetailPress,
  onToggleFavorite,
}: {
  favorite: boolean;
  favoriteDisabled: boolean;
  onDetailPress?: () => void;
  onToggleFavorite: () => void;
}) {
  return (
    <View style={styles.actions}>
      {onDetailPress ? (
        <TouchableOpacity accessibilityRole="button" onPress={onDetailPress} style={styles.iconButton}>
          <Eye color={colors.textMuted} size={17} />
        </TouchableOpacity>
      ) : null}
      <TouchableOpacity
        accessibilityRole="button"
        disabled={favoriteDisabled}
        onPress={onToggleFavorite}
        style={[styles.iconButton, favoriteDisabled && styles.iconButtonDisabled]}>
        <Heart color={favorite ? colors.danger : colors.textMuted} fill={favorite ? colors.danger : 'transparent'} size={17} />
      </TouchableOpacity>
    </View>
  );
}

function renderTags(tags: string[], onTagPress?: (tag: string) => void) {
  if (!tags.length) return null;
  return (
    <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.tags}>
      {tags.map(tag => (
        <TouchableOpacity key={tag} onPress={() => onTagPress?.(exactTagQuery(tag))}>
          <Text numberOfLines={1} style={styles.feedTag}>#{stripNamespace(tag).replace(/\s+/g, '')}</Text>
        </TouchableOpacity>
      ))}
    </ScrollView>
  );
}

function TweetPreview({items, loading, label}: {items: PreviewItem[]; loading: boolean; label: string}) {
  if (!items.length) return <PreviewPlaceholder loading={loading} label={label} />;
  const visible = items.slice(0, PREVIEW_LIMIT);
  if (visible.length === 1) return <View style={styles.tweetOne}>{renderTile(visible[0])}</View>;
  if (visible.length === 2) return <View style={styles.tweetTwo}>{visible.map(previewItem => renderTile(previewItem))}</View>;
  if (visible.length === 3) {
    return (
      <View style={styles.tweetThree}>
        <View style={styles.tweetThreeHero}>{renderTile(visible[0])}</View>
        <View style={styles.tweetThreeSide}>{visible.slice(1).map(previewItem => renderTile(previewItem))}</View>
      </View>
    );
  }
  return renderTweetGrid(visible);
}

function tweetGridRows(count: number) {
  if (count === 4) return [2, 2];
  if (count === 5) return [2, 3];
  if (count === 6) return [3, 3];
  if (count === 7) return [3, 2, 2];
  if (count === 8) return [3, 3, 2];
  return [3, 3, 3];
}

function renderTweetGrid(items: PreviewItem[]) {
  const rows: PreviewItem[][] = [];
  let offset = 0;
  for (const columns of tweetGridRows(items.length)) {
    rows.push(items.slice(offset, offset + columns));
    offset += columns;
  }
  const gridStyle = items.length <= 6 ? styles.tweetGridMedium : styles.tweetGridLarge;
  return (
    <View style={gridStyle}>
      {rows.map((row, rowIndex) => (
        <View key={`tweet-row-${rowIndex}`} style={styles.tweetGridRow}>
          {row.map(item => (
            <View key={item.id} style={styles.tweetGridCell}>{renderTile(item)}</View>
          ))}
        </View>
      ))}
    </View>
  );
}

function ChannelPreview({
  items,
  loading,
  label,
  width,
  onMeasure,
}: {
  items: PreviewItem[];
  loading: boolean;
  label: string;
  width: number;
  onMeasure: (measurementKey: string, aspectRatio: number) => void;
}) {
  if (!items.length) return <PreviewPlaceholder loading={loading} label={label} />;
  const layout = computeChannelPreviewLayout(items.slice(0, PREVIEW_LIMIT), width);
  if (layout.kind === 'single') {
    return <View style={[styles.channelSingle, {height: layout.heroHeight}]}>{renderTile(layout.hero, onMeasure)}</View>;
  }
  if (layout.kind === 'hero-side') {
    return (
      <View style={[styles.channelSplit, {height: layout.totalHeight}]}>
        <View style={[styles.channelHeroSide, {width: layout.heroWidth}]}>{renderTile(layout.hero, onMeasure)}</View>
        <View style={[styles.channelRows, styles.channelSideRows]}>
          {layout.rows.map((row, index) => renderChannelRow(row, index, onMeasure))}
        </View>
      </View>
    );
  }
  if (layout.kind === 'hero-top') {
    return (
      <View style={styles.channelRows}>
        <View style={{height: layout.heroHeight}}>{renderTile(layout.hero, onMeasure)}</View>
        {layout.rows.map((row, index) => renderChannelRow(row, index, onMeasure))}
      </View>
    );
  }
  return <View style={styles.channelRows}>{layout.rows.map((row, index) => renderChannelRow(row, index, onMeasure))}</View>;
}

function renderChannelRow(
  row: {height: number; items: Array<PreviewItem & {width: number}>},
  index: number,
  onMeasure: (measurementKey: string, aspectRatio: number) => void,
) {
  return (
    <View key={`row-${index}`} style={[styles.channelRow, {height: row.height}]}>
      {row.items.map(item => (
        <View key={item.id} style={[styles.channelRowItem, {width: item.width}]}>{renderTile(item, onMeasure)}</View>
      ))}
    </View>
  );
}

function renderTile(item: PreviewItem, onMeasure?: (measurementKey: string, aspectRatio: number) => void) {
  return (
    <View key={item.id} style={styles.tile}>
      {item.source ? (
        <FastImage
          source={item.source}
          resizeMode={FastImage.resizeMode.cover}
          style={styles.tileImage}
          onLoad={event => {
            const {width, height} = event.nativeEvent;
            if (width > 0 && height > 0) onMeasure?.(item.measurementKey, width / height);
          }}
        />
      ) : (
        <View style={styles.videoTile}><Film color={colors.textMuted} size={24} /></View>
      )}
      {item.kind !== 'image' ? (
        <View style={styles.videoBadge}><Film color={colors.white} size={13} /></View>
      ) : null}
    </View>
  );
}

function PreviewPlaceholder({loading, label}: {loading: boolean; label: string}) {
  return (
    <View style={styles.previewPlaceholder}>
      <Text numberOfLines={2} style={styles.placeholderText}>{loading ? '...' : label}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  actions: {
    flexDirection: 'row',
    gap: spacing.xs,
  },
  author: {
    color: colors.text,
    fontSize: 14,
    fontWeight: '800',
  },
  avatar: {
    alignItems: 'center',
    backgroundColor: colors.primaryMuted,
    borderRadius: 22,
    height: 44,
    justifyContent: 'center',
    width: 44,
  },
  avatarText: {
    color: colors.primary,
    fontSize: 15,
    fontWeight: '900',
  },
  card: {
    backgroundColor: colors.surface,
    borderColor: colors.border,
    borderRadius: 12,
    borderWidth: StyleSheet.hairlineWidth,
    marginBottom: spacing.md,
    overflow: 'hidden',
  },
  channelActionOverlay: {
    backgroundColor: 'rgba(255,255,255,0.88)',
    borderColor: colors.border,
    borderRadius: 20,
    borderWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: 4,
    paddingVertical: 3,
    position: 'absolute',
    right: 10,
    top: 10,
    zIndex: 2,
  },
  channelArticle: {
    alignItems: 'flex-end',
    flexDirection: 'row',
    gap: spacing.sm,
    marginBottom: spacing.md,
    paddingHorizontal: 4,
    paddingVertical: spacing.xs,
  },
  channelAvatar: {
    alignItems: 'center',
    backgroundColor: colors.primaryMuted,
    borderRadius: 20,
    height: 40,
    justifyContent: 'center',
    width: 40,
  },
  channelBody: {
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.md,
  },
  channelBubble: {
    backgroundColor: colors.surface,
    borderBottomLeftRadius: 6,
    borderColor: colors.border,
    borderRadius: 26,
    borderWidth: StyleSheet.hairlineWidth,
    flex: 1,
    minWidth: 0,
    overflow: 'hidden',
  },
  channelHeader: {
    gap: 2,
  },
  channelPreview: {
    overflow: 'hidden',
  },
  channelHeroSide: {
    height: '100%',
  },
  channelRow: {
    flexDirection: 'row',
    gap: 1,
  },
  channelRowItem: {
    height: '100%',
  },
  channelRows: {
    gap: 1,
  },
  channelSideRows: {
    flex: 1,
    overflow: 'hidden',
  },
  channelSingle: {
    backgroundColor: colors.border,
    width: '100%',
  },
  channelSplit: {
    backgroundColor: colors.border,
    flexDirection: 'row',
    gap: 1,
    overflow: 'hidden',
  },
  channelText: {
    color: colors.text,
    fontSize: 15,
    lineHeight: 22,
    marginTop: spacing.sm,
  },
  expandText: {
    color: colors.primary,
    fontSize: 13,
    fontWeight: '800',
    marginTop: spacing.xs,
  },
  feedTag: {
    color: colors.primary,
    fontSize: 13,
    fontWeight: '800',
  },
  headerText: {
    flex: 1,
    minWidth: 0,
  },
  iconButton: {
    alignItems: 'center',
    borderRadius: 18,
    height: 34,
    justifyContent: 'center',
    width: 34,
  },
  iconButtonDisabled: {
    opacity: 0.35,
  },
  meta: {
    color: colors.textMuted,
    fontSize: 12,
  },
  placeholderText: {
    color: colors.textMuted,
    fontSize: 13,
    textAlign: 'center',
  },
  previewAction: {
    color: colors.primary,
    flexShrink: 0,
    fontSize: 13,
    fontWeight: '900',
  },
  previewFooter: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: spacing.sm,
    justifyContent: 'space-between',
    padding: spacing.md,
  },
  previewPlaceholder: {
    alignItems: 'center',
    aspectRatio: 1.6,
    backgroundColor: colors.surfaceMuted,
    justifyContent: 'center',
    padding: spacing.md,
  },
  previewText: {
    flex: 1,
    minWidth: 0,
  },
  previewTitle: {
    color: colors.text,
    flex: 1,
    fontSize: 14,
    fontWeight: '800',
  },
  tags: {
    gap: spacing.md,
    paddingTop: spacing.sm,
  },
  tile: {
    backgroundColor: colors.surfaceMuted,
    height: '100%',
    overflow: 'hidden',
    width: '100%',
  },
  tileImage: {
    height: '100%',
    width: '100%',
  },
  tweetCard: {
    padding: spacing.md,
  },
  tweetContent: {
    flex: 1,
    minWidth: 0,
  },
  tweetGridCell: {
    flex: 1,
    minWidth: 0,
  },
  tweetGridLarge: {
    aspectRatio: 1,
    backgroundColor: colors.border,
    gap: 1,
  },
  tweetGridMedium: {
    aspectRatio: 1.5,
    backgroundColor: colors.border,
    gap: 1,
  },
  tweetGridRow: {
    flex: 1,
    flexDirection: 'row',
    gap: 1,
    minHeight: 0,
  },
  tweetHeader: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: spacing.sm,
  },
  tweetOne: {
    aspectRatio: 1.6,
    backgroundColor: colors.border,
  },
  tweetPreview: {
    borderColor: colors.border,
    borderRadius: 14,
    borderWidth: StyleSheet.hairlineWidth,
    marginTop: spacing.md,
    overflow: 'hidden',
  },
  tweetRow: {
    alignItems: 'flex-start',
    flexDirection: 'row',
    gap: spacing.sm,
  },
  tweetText: {
    color: colors.text,
    fontSize: 15,
    lineHeight: 22,
    marginTop: spacing.sm,
  },
  tweetThree: {
    aspectRatio: 1.6,
    backgroundColor: colors.border,
    flexDirection: 'row',
    gap: 1,
  },
  tweetThreeHero: {
    flex: 1,
  },
  tweetThreeSide: {
    flex: 1,
    gap: 1,
  },
  tweetTwo: {
    aspectRatio: 1.6,
    backgroundColor: colors.border,
    flexDirection: 'row',
    gap: 1,
  },
  videoBadge: {
    backgroundColor: 'rgba(0,0,0,0.55)',
    borderRadius: 14,
    padding: 6,
    position: 'absolute',
    right: 8,
    top: 8,
  },
  videoTile: {
    alignItems: 'center',
    flex: 1,
    justifyContent: 'center',
  },
});
