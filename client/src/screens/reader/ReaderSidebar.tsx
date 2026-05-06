import React, {useCallback, useEffect, useMemo, useState} from 'react';
import {
  FlatList,
  Image,
  type ImageSourcePropType,
  StyleSheet,
  Text,
  TouchableOpacity,
  useWindowDimensions,
  View,
} from 'react-native';
import {ChevronDown, ChevronRight, FileText, Film, Folder, ImageIcon, Music} from 'lucide-react-native';
import {VLCPlayer} from 'react-native-vlc-media-player';
import {spacing} from '../../theme/colors';
import {getStoredStringSync, setStoredStringSync} from '../../storage/mmkv';
import {useTheme} from '../../theme/ThemeContext';
import type {PageInfo} from '../../types/api';
import {Drawer} from '../../components/Drawer';

type SidebarTab = 'thumbnails' | 'list' | 'tree';
const SIDEBAR_TAB_KEY = 'reader_sidebar_tab';

function loadSidebarTab(): SidebarTab {
  const stored = getStoredStringSync(SIDEBAR_TAB_KEY);
  return stored === 'thumbnails' || stored === 'list' || stored === 'tree' ? stored : 'thumbnails';
}

type SbPage = {
  pageNumber: number;
  effectiveType: string;
  imageSource?: ImageSourcePropType | null;
  thumbnailSource?: ImageSourcePropType | null;
  uri?: string;
  vlcUri?: string;
  headers?: Record<string, string>;
  resolvedPath?: string;
  title?: string;
  metadata?: PageInfo['metadata'];
  activeSource?: PageInfo['defaultSource'];
};

type FileTreeFileNode = {
  kind: 'file';
  id: string;
  name: string;
  pageIndex: number;
  pageType: string;
};

type FileTreeFolderNode = {
  kind: 'folder';
  id: string;
  name: string;
  firstPageIndex: number;
  children: FileTreeNode[];
};

type FileTreeNode = FileTreeFileNode | FileTreeFolderNode;

type MutableFileTreeFolderNode = {
  id: string;
  name: string;
  firstPageIndex: number;
  folders: Map<string, MutableFileTreeFolderNode>;
  files: FileTreeFileNode[];
};

type Props = {
  open: boolean;
  pages: SbPage[];
  currentPage: number;
  onClose: () => void;
  onSelectPage: (pageIndex: number) => void;
  t: (key: string, params?: Record<string, string | number>) => string;
};

function pageTypeIcon(type: string, size: number, color: string) {
  switch (type) {
    case 'video':
      return <Film color={color} size={size} />;
    case 'audio':
      return <Music color={color} size={size} />;
    case 'html':
      return <FileText color={color} size={size} />;
    default:
      return <ImageIcon color={color} size={size} />;
  }
}

function getImageUri(source?: ImageSourcePropType | null) {
  return source && typeof source === 'object' && 'uri' in source && typeof source.uri === 'string'
    ? source.uri
    : '';
}

function getPagePathSegments(path: string): string[] {
  return String(path || '')
    .split('/')
    .map(segment => segment.trim())
    .filter(Boolean);
}

function getDisplayTitle(page: SbPage, pageIndex: number, t: Props['t']) {
  return (
    page.activeSource?.metadata?.title ||
    page.metadata?.title ||
    page.activeSource?.title ||
    page.title ||
    t('reader.pageNum', {page: pageIndex + 1})
  );
}

function getDisplayDescription(page: SbPage) {
  return page.activeSource?.metadata?.description || page.metadata?.description || '';
}

export function ReaderSidebar({open, pages, currentPage, onClose, onSelectPage, t}: Props) {
  const {colors} = useTheme();
  const {width: screenWidth, height: screenHeight} = useWindowDimensions();
  const [activeTab, setActiveTabState] = useState<SidebarTab>(loadSidebarTab);
  const setActiveTab = useCallback((tab: SidebarTab) => {
    setActiveTabState(tab);
    setStoredStringSync(SIDEBAR_TAB_KEY, tab);
  }, []);
  const [expandedFolderIds, setExpandedFolderIds] = useState<Set<string>>(new Set());
  const sidePanel = screenWidth >= 700 && screenWidth > screenHeight;
  const panelWidth = sidePanel ? Math.min(380, Math.max(320, Math.floor(screenWidth * 0.34))) : screenWidth;
  const thumbColumns = sidePanel ? 2 : 3;
  const thumbGap = 6;
  const thumbWidth = Math.floor((panelWidth - 48 - thumbGap * (thumbColumns - 1)) / thumbColumns);
  const thumbHeight = Math.floor(thumbWidth * 1.4);

  const styles = useMemo(
    () =>
      StyleSheet.create({
        sheet: {
          backgroundColor: colors.surface,
          padding: spacing.lg,
        },
        sideSheet: {
          backgroundColor: colors.surface,
          borderLeftColor: colors.border,
          borderLeftWidth: StyleSheet.hairlineWidth,
          paddingTop: spacing.lg,
          paddingHorizontal: spacing.lg,
        },
        sheetHandle: {
          alignSelf: 'center',
          backgroundColor: colors.borderStrong,
          borderRadius: 999,
          height: 4,
          marginBottom: spacing.md,
          width: 44,
        },
        sheetHeader: {
          alignItems: 'center',
          flexDirection: 'row',
          gap: spacing.sm,
          justifyContent: 'space-between',
          marginBottom: spacing.md,
        },
        sheetTitle: {
          color: colors.text,
          flex: 1,
          fontSize: 18,
          fontWeight: '800',
        },
        sideCloseButton: {
          alignItems: 'center',
          borderColor: colors.border,
          borderRadius: 16,
          borderWidth: StyleSheet.hairlineWidth,
          height: 32,
          justifyContent: 'center',
          width: 32,
        },
        sideCloseButtonText: {
          color: colors.textMuted,
          fontSize: 14,
          fontWeight: '800',
        },
        tabBar: {
          flexDirection: 'row',
          gap: spacing.sm,
          marginBottom: spacing.md,
        },
        tab: {
          borderColor: colors.border,
          borderRadius: 8,
          borderWidth: StyleSheet.hairlineWidth,
          paddingHorizontal: 12,
          paddingVertical: 9,
        },
        tabActive: {
          backgroundColor: colors.primaryMuted,
          borderColor: colors.primary,
        },
        tabText: {
          color: colors.textMuted,
          fontSize: 14,
          fontWeight: '800',
        },
        tabTextActive: {
          color: colors.primary,
        },
        thumbContent: {
          paddingBottom: spacing.sm,
        },
        thumbRow: {
          gap: 6,
          marginBottom: 6,
        },
        thumbItem: {
          alignItems: 'center',
        },
        thumbFrame: {
          backgroundColor: '#f0f0f0',
          borderRadius: 6,
          overflow: 'hidden',
        },
        thumbFrameActive: {
          borderColor: colors.primary,
          borderWidth: 2.5,
        },
        thumbImage: {
          borderRadius: 6,
        },
        thumbPlaceholder: {
          alignItems: 'center',
          backgroundColor: '#e8e8e8',
          borderRadius: 6,
          justifyContent: 'center',
        },
        thumbBadge: {
          backgroundColor: colors.primary,
          borderBottomLeftRadius: 6,
          paddingHorizontal: 6,
          paddingVertical: 2,
          position: 'absolute',
          right: 0,
          top: 0,
        },
        thumbBadgeText: {
          color: colors.white,
          fontSize: 9,
          fontWeight: '800',
        },
        thumbLabel: {
          color: colors.textMuted,
          fontSize: 11,
          fontWeight: '700',
          marginTop: 3,
          textAlign: 'center',
        },
        thumbLabelActive: {
          color: colors.primary,
        },
        listContent: {
          paddingBottom: spacing.sm,
        },
        listRow: {
          alignItems: 'center',
          borderColor: colors.border,
          borderRadius: 8,
          borderWidth: StyleSheet.hairlineWidth,
          flexDirection: 'row',
          marginBottom: 6,
          paddingHorizontal: 10,
          paddingVertical: 10,
        },
        listRowActive: {
          backgroundColor: colors.primaryMuted,
          borderColor: colors.primary,
        },
        listIcon: {
          alignItems: 'center',
          height: 28,
          justifyContent: 'center',
          marginRight: 10,
          width: 28,
        },
        listThumb: {
          backgroundColor: colors.surfaceMuted,
          borderRadius: 6,
          height: 42,
          marginRight: 10,
          width: 58,
        },
        listInfo: {
          flex: 1,
          minWidth: 0,
        },
        listPageNum: {
          color: colors.text,
          fontSize: 14,
          fontWeight: '700',
        },
        listPageNumActive: {
          color: colors.primary,
        },
        listFileName: {
          color: colors.textMuted,
          fontSize: 11,
          marginTop: 2,
        },
        listType: {
          color: colors.textMuted,
          fontSize: 11,
          fontWeight: '700',
          marginLeft: 8,
        },
        listTypeActive: {
          color: colors.primary,
        },
        treeRow: {
          alignItems: 'center',
          borderRadius: 7,
          flexDirection: 'row',
          gap: 6,
          minHeight: 32,
          paddingRight: 8,
        },
        treeRowActive: {
          backgroundColor: colors.primaryMuted,
        },
        treeFolderText: {
          color: colors.text,
          flex: 1,
          fontSize: 13,
          fontWeight: '700',
          minWidth: 0,
        },
        treeFileText: {
          color: colors.text,
          flex: 1,
          fontSize: 12,
          minWidth: 0,
        },
        treeFileTextActive: {
          color: colors.primary,
          fontWeight: '800',
        },
        treePageText: {
          color: colors.textMuted,
          fontSize: 10,
          fontWeight: '700',
        },
        closeButton: {
          alignItems: 'center',
          backgroundColor: colors.primary,
          borderRadius: 8,
          marginTop: spacing.md,
          paddingVertical: 12,
        },
        closeButtonText: {
          color: colors.white,
          fontSize: 15,
          fontWeight: '800',
        },
      }),
    [colors],
  );

  useEffect(() => {
    if (open) {
      setActiveTab('thumbnails');
    }
  }, [open]);

  const handleSelect = useCallback(
    (pageIndex: number) => {
      onSelectPage(pageIndex);
      if (!sidePanel) onClose();
    },
    [onSelectPage, onClose, sidePanel],
  );

  const fileTree = useMemo(() => {
    const root: MutableFileTreeFolderNode = {
      id: '',
      name: '',
      firstPageIndex: 0,
      folders: new Map(),
      files: [],
    };
    const allFolderIds = new Set<string>();
    const topLevelFolderIds = new Set<string>();
    const pageAncestors: Record<number, string[]> = {};

    pages.forEach((page, pageIndex) => {
      const fallbackName = getDisplayTitle(page, pageIndex, t);
      const segments = getPagePathSegments(page.resolvedPath || getImageUri(page.imageSource) || page.uri || '');
      const fileName = segments[segments.length - 1] || fallbackName;
      const folderSegments = segments.length > 1 ? segments.slice(0, -1) : [];
      let folder = root;
      let folderPath = '';
      const ancestors: string[] = [];

      folderSegments.forEach((segment, depth) => {
        const folderId = folderPath ? `${folderPath}/${segment}` : segment;
        let next = folder.folders.get(segment);
        if (!next) {
          next = {
            id: folderId,
            name: segment,
            firstPageIndex: pageIndex,
            folders: new Map(),
            files: [],
          };
          folder.folders.set(segment, next);
          allFolderIds.add(folderId);
          if (depth === 0) topLevelFolderIds.add(folderId);
        } else if (pageIndex < next.firstPageIndex) {
          next.firstPageIndex = pageIndex;
        }

        folder = next;
        folderPath = folderId;
        ancestors.push(folderId);
      });

      const fileIdBase = folderPath ? `${folderPath}/${fileName}` : fileName;
      folder.files.push({
        kind: 'file',
        id: `${fileIdBase}#${pageIndex}`,
        name: fileName,
        pageIndex,
        pageType: page.effectiveType,
      });
      pageAncestors[pageIndex] = ancestors;
    });

    const compareNames = (a: string, b: string) => a.localeCompare(b, undefined, {numeric: true, sensitivity: 'base'});
    const convertTree = (folder: MutableFileTreeFolderNode): FileTreeNode[] => {
      const folders = [...folder.folders.values()]
        .sort((a, b) => compareNames(a.name, b.name))
        .map<FileTreeFolderNode>(child => ({
          kind: 'folder',
          id: child.id,
          name: child.name,
          firstPageIndex: child.firstPageIndex,
          children: convertTree(child),
        }));
      const files = [...folder.files].sort((a, b) => compareNames(a.name, b.name));
      return [...folders, ...files];
    };

    return {
      nodes: convertTree(root),
      allFolderIds: [...allFolderIds],
      topLevelFolderIds: [...topLevelFolderIds],
      pageAncestors,
    };
  }, [pages, t]);

  useEffect(() => {
    const validFolders = new Set(fileTree.allFolderIds);
    if (validFolders.size === 0) {
      setExpandedFolderIds(prev => (prev.size === 0 ? prev : new Set()));
      return;
    }

    setExpandedFolderIds(prev => {
      const next = new Set<string>();
      prev.forEach(folderId => {
        if (validFolders.has(folderId)) next.add(folderId);
      });

      if (next.size === 0) {
        fileTree.topLevelFolderIds.forEach(folderId => next.add(folderId));
      }

      const activeAncestors = fileTree.pageAncestors[currentPage - 1] || [];
      activeAncestors.forEach(folderId => {
        if (validFolders.has(folderId)) next.add(folderId);
      });

      if (next.size === prev.size && [...next].every(folderId => prev.has(folderId))) {
        return prev;
      }
      return next;
    });
  }, [currentPage, fileTree]);

  const toggleFolder = useCallback((folderId: string) => {
    setExpandedFolderIds(prev => {
      const next = new Set(prev);
      if (next.has(folderId)) {
        next.delete(folderId);
      } else {
        next.add(folderId);
      }
      return next;
    });
  }, []);

  const renderThumbnailItem = useCallback(
    ({item, index}: {item: SbPage; index: number}) => {
      const pageIdx = index; // 0-based
      const isCurrent = pageIdx + 1 === currentPage;
      const thumbSource = item.thumbnailSource || item.imageSource;
      const thumbSrc = getImageUri(thumbSource) || item.uri;
      const videoPreviewUri = item.effectiveType === 'video' ? item.vlcUri || item.uri || '' : '';
      return (
        <TouchableOpacity
          activeOpacity={0.7}
          onPress={() => handleSelect(pageIdx)}
          style={[styles.thumbItem, {width: thumbWidth}]}>
          <View
            style={[
              styles.thumbFrame,
              {width: thumbWidth, height: thumbHeight},
              isCurrent && styles.thumbFrameActive,
            ]}>
            {item.effectiveType === 'video' && videoPreviewUri ? (
              <VLCPlayer
                autoplay
                muted
                paused={false}
                resizeMode="cover"
                source={
                  {
                    uri: videoPreviewUri,
                    isNetwork: Boolean(videoPreviewUri.startsWith('http')),
                    initType: 2,
                    initOptions: ['--network-caching=300', ''],
                    mediaOptions: [':no-audio', ':http-reconnect', ''],
                  } as never
                }
                style={[styles.thumbImage, {width: thumbWidth, height: thumbHeight}]}
                volume={0}
              />
            ) : thumbSrc ? (
              <Image
                resizeMode="cover"
                source={thumbSource || {uri: thumbSrc, headers: item.headers}}
                style={[styles.thumbImage, {width: thumbWidth, height: thumbHeight}]}
              />
            ) : (
              <View style={[styles.thumbPlaceholder, {width: thumbWidth, height: thumbHeight}]}>
                {pageTypeIcon(item.effectiveType, 24, '#8a8a8a')}
              </View>
            )}
            {isCurrent && (
              <View style={styles.thumbBadge}>
                <Text style={styles.thumbBadgeText}>{t('reader.current')}</Text>
              </View>
            )}
          </View>
          <Text
            numberOfLines={1}
            style={[styles.thumbLabel, isCurrent && styles.thumbLabelActive]}>
            {pageIdx + 1}
          </Text>
        </TouchableOpacity>
      );
    },
    [currentPage, handleSelect, thumbWidth, thumbHeight, t],
  );

  const renderListItem = useCallback(
    ({item, index}: {item: SbPage; index: number}) => {
      const pageIdx = index;
      const isCurrent = pageIdx + 1 === currentPage;
      const displayTitle = getDisplayTitle(item, pageIdx, t);
      const description = getDisplayDescription(item);
      const pagePathSegments = getPagePathSegments(item.resolvedPath || '');
      const fileName = pagePathSegments[pagePathSegments.length - 1] || '';
      const subtitle = fileName && fileName !== displayTitle ? fileName : description;
      const thumbSource = item.thumbnailSource;
      return (
        <TouchableOpacity
          activeOpacity={0.7}
          onPress={() => handleSelect(pageIdx)}
          style={[styles.listRow, isCurrent && styles.listRowActive]}>
          {thumbSource ? (
            <Image resizeMode="cover" source={thumbSource} style={styles.listThumb} />
          ) : (
            <View style={styles.listIcon}>
              {pageTypeIcon(item.effectiveType, 16, isCurrent ? colors.primary : '#8a8a8a')}
            </View>
          )}
          <View style={styles.listInfo}>
            <Text
              numberOfLines={1}
              style={[styles.listPageNum, isCurrent && styles.listPageNumActive]}>
              {displayTitle}
            </Text>
            {subtitle ? (
              <Text numberOfLines={1} style={styles.listFileName}>
                {subtitle}
              </Text>
            ) : null}
          </View>
          <Text style={[styles.listType, isCurrent && styles.listTypeActive]}>
            {pageIdx + 1}
          </Text>
        </TouchableOpacity>
      );
    },
    [currentPage, handleSelect, t],
  );

  const keyExtractor = useCallback(
    (item: SbPage, index: number) => `sidebar-${item.pageNumber}-${index}`,
    [],
  );

  const renderFileTreeNode = useCallback(
    (node: FileTreeNode, depth: number): React.ReactNode => {
      const paddingLeft = 6 + depth * 14;

      if (node.kind === 'folder') {
        const isExpanded = expandedFolderIds.has(node.id);
        return (
          <View key={node.id}>
            <TouchableOpacity
              activeOpacity={0.7}
              onPress={() => toggleFolder(node.id)}
              style={[styles.treeRow, {paddingLeft}]}>
              {isExpanded ? (
                <ChevronDown color={colors.textMuted} size={14} />
              ) : (
                <ChevronRight color={colors.textMuted} size={14} />
              )}
              <Folder color={colors.primary} size={16} />
              <Text numberOfLines={1} style={styles.treeFolderText}>
                {node.name}
              </Text>
            </TouchableOpacity>
            {isExpanded ? node.children.map(child => renderFileTreeNode(child, depth + 1)) : null}
          </View>
        );
      }

      const isCurrent = node.pageIndex + 1 === currentPage;
      return (
        <TouchableOpacity
          activeOpacity={0.7}
          key={node.id}
          onPress={() => handleSelect(node.pageIndex)}
          style={[styles.treeRow, {paddingLeft}, isCurrent && styles.treeRowActive]}>
          {pageTypeIcon(node.pageType, 15, isCurrent ? colors.primary : colors.textMuted)}
          <Text numberOfLines={1} style={[styles.treeFileText, isCurrent && styles.treeFileTextActive]}>
            {node.name}
          </Text>
          <Text style={[styles.treePageText, isCurrent && styles.treeFileTextActive]}>
            {node.pageIndex + 1}
          </Text>
        </TouchableOpacity>
      );
    },
    [currentPage, expandedFolderIds, handleSelect, toggleFolder],
  );

  return (
    <Drawer
      open={open}
      onClose={onClose}
      side={sidePanel ? 'right' : 'bottom'}
      showHandle={!sidePanel}
      enablePanDownToClose={!sidePanel}
      maxHeight={sidePanel ? '100%' : '82%'}
      style={sidePanel ? {width: panelWidth} : undefined}>
      <View style={sidePanel ? styles.sideSheet : styles.sheet}>
        <View style={styles.sheetHeader}>
          <Text style={styles.sheetTitle}>{t('reader.sidebar')}</Text>
          {sidePanel ? (
            <TouchableOpacity onPress={onClose} style={styles.sideCloseButton}>
              <Text style={styles.sideCloseButtonText}>x</Text>
            </TouchableOpacity>
          ) : null}
        </View>

        <View style={styles.tabBar}>
          <TouchableOpacity
            onPress={() => setActiveTab('thumbnails')}
            style={[styles.tab, activeTab === 'thumbnails' && styles.tabActive]}>
            <Text
              style={[styles.tabText, activeTab === 'thumbnails' && styles.tabTextActive]}>
              {t('reader.thumbnails')}
            </Text>
          </TouchableOpacity>
          <TouchableOpacity
            onPress={() => setActiveTab('list')}
            style={[styles.tab, activeTab === 'list' && styles.tabActive]}>
            <Text
              style={[styles.tabText, activeTab === 'list' && styles.tabTextActive]}>
              {t('reader.listTab')}
            </Text>
          </TouchableOpacity>
          <TouchableOpacity
            onPress={() => setActiveTab('tree')}
            style={[styles.tab, activeTab === 'tree' && styles.tabActive]}>
            <Text
              style={[styles.tabText, activeTab === 'tree' && styles.tabTextActive]}>
              {t('reader.fileTree')}
            </Text>
          </TouchableOpacity>
        </View>

        {activeTab === 'thumbnails' ? (
          <FlatList
            data={pages}
            key={`thumb-${thumbColumns}`}
            keyExtractor={keyExtractor}
            numColumns={thumbColumns}
            columnWrapperStyle={styles.thumbRow}
            contentContainerStyle={styles.thumbContent}
            renderItem={renderThumbnailItem}
            showsVerticalScrollIndicator={false}
          />
        ) : activeTab === 'tree' ? (
          <FlatList
            data={fileTree.nodes}
            keyExtractor={item => item.id}
            contentContainerStyle={styles.listContent}
            renderItem={({item}) => renderFileTreeNode(item, 0) as React.ReactElement}
            showsVerticalScrollIndicator={false}
          />
        ) : (
          <FlatList
            data={pages}
            keyExtractor={keyExtractor}
            contentContainerStyle={styles.listContent}
            renderItem={renderListItem}
            showsVerticalScrollIndicator={false}
          />
        )}

        {!sidePanel ? (
          <TouchableOpacity onPress={onClose} style={styles.closeButton}>
            <Text style={styles.closeButtonText}>{t('common.close')}</Text>
          </TouchableOpacity>
        ) : null}
      </View>
    </Drawer>
  );
}

