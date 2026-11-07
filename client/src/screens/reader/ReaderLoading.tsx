import React from 'react';
import {StyleSheet, Text, View} from 'react-native';

import {CircularProgress} from '../../components/CircularProgress';

import {useReaderPageLoadState} from './pageLoadState';

// Reader chrome is always black-on-black in both themes.
const palette = {black: '#000000', white: '#ffffff'};

type PhaseLabels = {
  queued: string;
  loading: string;
  downloading: string;
  error: string;
};

type Props = {
  pageNumber: number;
  minHeight: number;
  labels: PhaseLabels;
};

/**
 * Per-page placeholder shown while that page is queued, downloading or failed.
 * Mihon keeps a full-viewport progress container on every webtoon holder so
 * RecyclerView does not inflate extra blank views to fill the screen; this is
 * the equivalent for VirtualizedList.
 */
export function ReaderPageLoading({pageNumber, minHeight, labels}: Props) {
  const state = useReaderPageLoadState(pageNumber);
  const label =
    state.phase === 'queued'
      ? labels.queued
      : state.phase === 'loading'
        ? labels.loading
        : state.phase === 'downloading'
          ? labels.downloading
          : state.phase === 'error'
            ? labels.error
            : '';
  const indeterminate = state.phase !== 'downloading' || state.progress <= 0;
  return (
    <View pointerEvents="none" style={[styles.container, {minHeight}]}>
      <CircularProgress
        color={palette.white}
        indeterminate={indeterminate}
        showLabel={!indeterminate}
        size={54}
        value={state.progress}
      />
      <Text style={styles.pageNumber}>{pageNumber}</Text>
      {label ? <Text style={styles.label}>{label}</Text> : null}
    </View>
  );
}

/**
 * Whole-reader loading state, shown only while the archive page list is being
 * fetched. It is deliberately separate from the per-page placeholder: the list
 * must not be blank while pages are still streaming in one by one.
 */
export function ReaderLoadingState({
  title,
  detail,
}: {
  title: string;
  detail?: string;
}) {
  return (
    <View style={styles.readerContainer}>
      <CircularProgress color={palette.white} indeterminate showLabel={false} size={64} />
      <Text style={styles.readerTitle}>{title}</Text>
      {detail ? <Text style={styles.readerDetail}>{detail}</Text> : null}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    alignItems: 'center',
    alignSelf: 'stretch',
    backgroundColor: palette.black,
    justifyContent: 'center',
    paddingVertical: 32,
  },
  pageNumber: {
    color: palette.white,
    fontSize: 18,
    fontWeight: '600',
    marginTop: 14,
    opacity: 0.82,
  },
  label: {
    color: palette.white,
    fontSize: 12,
    marginTop: 6,
    opacity: 0.6,
  },
  readerContainer: {
    alignItems: 'center',
    backgroundColor: palette.black,
    flex: 1,
    justifyContent: 'center',
    padding: 24,
  },
  readerTitle: {
    color: palette.white,
    fontSize: 15,
    fontWeight: '600',
    marginTop: 22,
  },
  readerDetail: {
    color: palette.white,
    fontSize: 12,
    marginTop: 8,
    opacity: 0.65,
    textAlign: 'center',
  },
});
