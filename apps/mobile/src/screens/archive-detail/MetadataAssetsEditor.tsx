import React, {useEffect, useMemo, useState} from 'react';
import {StyleSheet, Text, TouchableOpacity, View} from 'react-native';
import FastImage, {type Source as FastImageSource} from '@d11/react-native-fast-image';

import {buildAuthorizedAssetImageSource} from '../../api/client';
import {useTheme} from '../../theme/ThemeContext';
import type {TFunction} from '../../i18n';

type Props = {
  t: TFunction;
  title: string;
  disabled?: boolean;
  coverAssetId: string;
  onUploadCover: () => void;
  backdropAssetId: string;
  onUploadBackdrop: () => void;
  clearlogoAssetId: string;
  onUploadClearlogo: () => void;
  uploadingCover: boolean;
  uploadingBackdrop: boolean;
  uploadingClearlogo: boolean;
};

function parseAssetId(raw: string): number {
  const n = Number.parseInt(String(raw || '').trim(), 10);
  if (!Number.isFinite(n) || n <= 0) return 0;
  return n;
}

function resolveImageUrl(rawValue: string): string | null {
  const value = String(rawValue || '').trim();
  if (!value) return null;
  if (/^\d+$/.test(value)) {
    const id = Number.parseInt(value, 10);
    return id > 0 ? `/api/assets/${id}` : null;
  }
  if (value.startsWith('/') || /^https?:\/\//i.test(value)) {
    return value;
  }
  return null;
}

function AssetImage({assetId, style}: {assetId: string; style: any}) {
  const [source, setSource] = useState<FastImageSource | null>(null);

  useEffect(() => {
    const id = parseAssetId(assetId);
    if (id > 0) {
      buildAuthorizedAssetImageSource(id).then(setSource).catch(() => setSource(null));
    } else {
      setSource(null);
    }
  }, [assetId]);

  if (!source) {
    return <View style={[style, {backgroundColor: '#333'}]} />;
  }

  return (
    <FastImage
      source={source}
      style={style}
      resizeMode={FastImage.resizeMode.cover}
    />
  );
}

export function MetadataAssetsEditor({
  t,
  title,
  disabled = false,
  coverAssetId,
  onUploadCover,
  backdropAssetId,
  onUploadBackdrop,
  clearlogoAssetId,
  onUploadClearlogo,
  uploadingCover,
  uploadingBackdrop,
  uploadingClearlogo,
}: Props) {
  const {colors} = useTheme();

  const hasBackdrop = parseAssetId(backdropAssetId) > 0;
  const hasCover = parseAssetId(coverAssetId) > 0;
  const hasClearlogo = parseAssetId(clearlogoAssetId) > 0;

  const styles = useMemo(
    () =>
      StyleSheet.create({
        container: {
          borderRadius: 8,
          height: 180,
          overflow: 'hidden',
          position: 'relative',
        },
        backdrop: {
          height: '100%',
          position: 'absolute',
          width: '100%',
        },
        backdropPlaceholder: {
          height: '100%',
          position: 'absolute',
          width: '100%',
        },
        gradient: {
          bottom: 0,
          left: 0,
          position: 'absolute',
          right: 0,
          top: 0,
        },
        backdropButton: {
          alignItems: 'center',
          backgroundColor: 'rgba(0,0,0,0.45)',
          borderRadius: 18,
          height: 30,
          justifyContent: 'center',
          position: 'absolute',
          right: 8,
          top: 8,
          width: 30,
          zIndex: 20,
        },
        uploadIcon: {
          color: colors.white,
          fontSize: 14,
          fontWeight: '800',
        },
        coverWrap: {
          borderColor: 'rgba(255,255,255,0.8)',
          borderRadius: 6,
          borderWidth: 2,
          bottom: 16,
          height: 130,
          left: 16,
          overflow: 'hidden',
          position: 'absolute',
          width: 92,
          zIndex: 10,
        },
        coverPlaceholder: {
          alignItems: 'center',
          backgroundColor: 'rgba(0,0,0,0.35)',
          flex: 1,
          justifyContent: 'center',
        },
        coverButton: {
          alignItems: 'center',
          backgroundColor: 'rgba(0,0,0,0.45)',
          borderRadius: 16,
          height: 28,
          justifyContent: 'center',
          position: 'absolute',
          right: 4,
          top: 4,
          width: 28,
          zIndex: 11,
        },
        clearlogoArea: {
          bottom: 24,
          left: 124,
          position: 'absolute',
          right: 16,
          zIndex: 10,
        },
        clearlogoText: {
          color: 'rgba(255,255,255,0.85)',
          fontSize: 18,
          fontWeight: '700',
        },
        clearlogoButton: {
          alignItems: 'center',
          backgroundColor: 'rgba(0,0,0,0.45)',
          borderRadius: 16,
          height: 28,
          justifyContent: 'center',
          position: 'absolute',
          right: 0,
          top: -34,
          width: 28,
          zIndex: 12,
        },
        clearlogoImage: {
          height: 36,
          width: 100,
        },
      }),
    [colors],
  );

  return (
    <View style={styles.container}>
      {/* Backdrop layer */}
      <View style={styles.backdrop}>
        {hasBackdrop ? (
          <AssetImage assetId={backdropAssetId} style={{flex: 1}} />
        ) : (
          <View style={[styles.backdropPlaceholder, {backgroundColor: colors.surfaceMuted}]} />
        )}
      </View>
      <View style={[styles.gradient, {backgroundColor: 'rgba(0,0,0,0.35)'}]} />

      {/* Backdrop upload button */}
      <TouchableOpacity
        style={styles.backdropButton}
        onPress={onUploadBackdrop}
        disabled={disabled || uploadingBackdrop}>
        <Text style={styles.uploadIcon}>
          {uploadingBackdrop ? '...' : '+'}
        </Text>
      </TouchableOpacity>

      {/* Cover */}
      <View style={styles.coverWrap}>
        {hasCover ? (
          <AssetImage assetId={coverAssetId} style={{flex: 1}} />
        ) : (
          <View style={styles.coverPlaceholder}>
            <Text style={{color: 'rgba(255,255,255,0.5)', fontSize: 10}}>
              {t('archive.noCover')}
            </Text>
          </View>
        )}
        <TouchableOpacity
          style={styles.coverButton}
          onPress={onUploadCover}
          disabled={disabled || uploadingCover}>
          <Text style={styles.uploadIcon}>
            {uploadingCover ? '...' : '+'}
          </Text>
        </TouchableOpacity>
      </View>

      {/* Clearlogo */}
      <View style={styles.clearlogoArea}>
        {hasClearlogo ? (
          <AssetImage assetId={clearlogoAssetId} style={styles.clearlogoImage} />
        ) : (
          <Text style={styles.clearlogoText} numberOfLines={1}>
            {title || t('archive.titleField')}
          </Text>
        )}
        <TouchableOpacity
          style={styles.clearlogoButton}
          onPress={onUploadClearlogo}
          disabled={disabled || uploadingClearlogo}>
          <Text style={styles.uploadIcon}>
            {uploadingClearlogo ? '...' : '+'}
          </Text>
        </TouchableOpacity>
      </View>
    </View>
  );
}
