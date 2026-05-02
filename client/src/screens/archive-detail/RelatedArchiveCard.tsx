import React, {useEffect, useState} from 'react';
import {StyleSheet, Text, TouchableOpacity, View} from 'react-native';
import FastImage, {type Source as FastImageSource} from '@d11/react-native-fast-image';

import {archiveCoverAsset, assetPath} from '../../api/lanlu';
import {buildAuthorizedImageSource} from '../../api/client';
import {colors} from '../../theme/colors';
import type {Archive} from '../../types/api';

type Props = {
  archive: Archive;
  onPress: (archive: Archive) => void;
};

export function RelatedArchiveCard({archive, onPress}: Props) {
  const [cover, setCover] = useState<FastImageSource | null>(null);

  useEffect(() => {
    let cancelled = false;
    const ca = archiveCoverAsset(archive);
    if (ca) {
      const path = assetPath(ca);
      if (path) {
        buildAuthorizedImageSource(path)
          .then((src: FastImageSource | null) => {
            if (!cancelled) setCover(src);
          })
          .catch(() => {
            if (!cancelled) setCover(null);
          });
        return;
      }
    }
    setCover(null);
    return () => {
      cancelled = true;
    };
  }, [archive]);

  return (
    <TouchableOpacity style={styles.card} onPress={() => onPress(archive)}>
      {cover ? (
        <FastImage
          source={cover}
          style={styles.cover}
          resizeMode={FastImage.resizeMode.cover}
        />
      ) : (
        <View style={[styles.cover, styles.coverPlaceholder]} />
      )}
      <Text style={styles.title} numberOfLines={2}>
        {archive.title || archive.filename}
      </Text>
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  card: {
    width: 120,
  },
  cover: {
    aspectRatio: 0.72,
    backgroundColor: colors.surfaceMuted,
    borderRadius: 6,
    width: '100%',
  },
  coverPlaceholder: {},
  title: {
    color: colors.text,
    fontSize: 12,
    marginTop: 4,
  },
});
