import React, {useCallback, useMemo, useState} from 'react';
import {LayoutChangeEvent, StyleSheet, Text, View} from 'react-native';
import Svg, {Rect, Text as SvgText} from 'react-native-svg';
import {TrendingUp} from 'lucide-react-native';
import {useTheme} from '../theme/ThemeContext';
import {useI18n} from '../i18n';
import {spacing, radius, type ThemeColors} from '../theme/colors';

type DataPoint = {
  date: string;
  count: number;
};

const CHART_HEIGHT = 170;
const PADDING = {top: 14, right: 8, bottom: 22, left: 34};

function formatDate(dateStr: string): string {
  const d = new Date(dateStr);
  return `${d.getMonth() + 1}/${d.getDate()}`;
}

export function ReadingTrendChart({data, loading}: {data: DataPoint[]; loading: boolean}) {
  const {colors} = useTheme();
  const {t} = useI18n();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const [containerWidth, setContainerWidth] = useState(0);

  const onLayout = useCallback((e: LayoutChangeEvent) => {
    setContainerWidth(e.nativeEvent.layout.width);
  }, []);

  const chartWidth = Math.max(0, containerWidth - PADDING.left - PADDING.right);
  const chartHeight = CHART_HEIGHT - PADDING.top - PADDING.bottom;

  const {bars, yLabels, xLabels} = useMemo(() => {
    if (data.length === 0 || containerWidth <= 0) {
      return {
        bars: [] as {x: number; y: number; w: number; h: number; active: boolean}[],
        yLabels: [] as {y: number; label: string}[],
        xLabels: [] as {x: number; label: string}[],
      };
    }
    const maxVal = Math.max(...data.map(d => d.count), 5);
    // One slot per day, bars take 68% of the slot so gaps stay even.
    const slot = chartWidth / data.length;
    const barWidth = Math.max(2, Math.min(slot * 0.68, 18));

    const barsOut = data.map((d, i) => {
      const h = maxVal > 0 ? (d.count / maxVal) * chartHeight : 0;
      return {
        x: PADDING.left + i * slot + (slot - barWidth) / 2,
        y: PADDING.top + chartHeight - h,
        w: barWidth,
        h: Math.max(d.count > 0 ? 2 : 0, h),
        active: d.count > 0,
      };
    });

    const steps = 3;
    const yLbls = Array.from({length: steps + 1}, (_, i) => {
      const val = Math.round((maxVal / steps) * i);
      return {
        y: PADDING.top + chartHeight - (val / maxVal) * chartHeight,
        label: String(val),
      };
    });

    // Label roughly every 6th day so 30 days render ~5 marks without overlap.
    const labelStride = Math.max(1, Math.ceil(data.length / 5));
    const xLbls = data
      .map((d, i) => ({x: PADDING.left + i * slot + slot / 2, label: formatDate(d.date), i}))
      .filter(entry => entry.i % labelStride === 0)
      .map(({x, label}) => ({x, label}));

    return {bars: barsOut, yLabels: yLbls, xLabels: xLbls};
  }, [data, chartWidth, chartHeight, containerWidth]);

  const summary = useMemo(() => {
    if (data.length === 0) return null;
    let maxCount = 0;
    let maxDate = '';
    let daysWithReads = 0;
    let total = 0;
    for (const d of data) {
      if (d.count > maxCount) {
        maxCount = d.count;
        maxDate = d.date;
      }
      if (d.count > 0) daysWithReads++;
      total += d.count;
    }
    return {maxDate: formatDate(maxDate), maxCount, daysWithReads, total};
  }, [data]);

  if (loading) {
    return <View style={[styles.placeholder, {height: CHART_HEIGHT}]} />;
  }

  return (
    <View style={styles.container}>
      <View style={styles.titleRow}>
        <TrendingUp color={colors.text} size={18} />
        <Text style={styles.title}>{t('dashboard.readingTrend')}</Text>
      </View>
      {data.length === 0 ? (
        <View style={[styles.emptyContainer, {height: CHART_HEIGHT}]}>
          <Text style={styles.emptyText}>{t('dashboard.noTrendData')}</Text>
        </View>
      ) : (
        <View onLayout={onLayout}>
          {containerWidth > 0 && (
            <Svg width={containerWidth} height={CHART_HEIGHT}>
              {yLabels.map((yl, i) => (
                <React.Fragment key={`y-${i}`}>
                  {i > 0 ? (
                    <Rect
                      x={PADDING.left}
                      y={yl.y}
                      width={chartWidth}
                      height={1}
                      fill={colors.border}
                    />
                  ) : null}
                  <SvgText
                    x={PADDING.left - 6}
                    y={yl.y + 4}
                    fill={colors.textMuted}
                    fontSize={10}
                    textAnchor="end">
                    {yl.label}
                  </SvgText>
                </React.Fragment>
              ))}
              {bars.map((bar, i) => (
                <Rect
                  key={`bar-${i}`}
                  x={bar.x}
                  y={bar.y}
                  width={bar.w}
                  height={bar.h}
                  rx={2}
                  fill={bar.active ? colors.primary : colors.border}
                />
              ))}
              {xLabels.map((xl, i) => (
                <SvgText
                  key={`x-${i}`}
                  x={xl.x}
                  y={CHART_HEIGHT - 6}
                  fill={colors.textMuted}
                  fontSize={10}
                  textAnchor="middle">
                  {xl.label}
                </SvgText>
              ))}
            </Svg>
          )}
        </View>
      )}
      {summary && (
        <View style={styles.summary}>
          <View style={styles.summaryItem}>
            <Text style={styles.summaryLabel}>{t('dashboard.readCount')}</Text>
            <Text style={styles.summaryValue}>{summary.total}</Text>
          </View>
          <View style={styles.summaryItem}>
            <Text style={styles.summaryLabel}>{t('dashboard.mostActiveDay')}</Text>
            <Text style={styles.summaryValue}>{summary.maxDate}</Text>
          </View>
          <View style={styles.summaryItem}>
            <Text style={styles.summaryLabel}>{t('dashboard.daysWithReads')}</Text>
            <Text style={styles.summaryValue}>{summary.daysWithReads}</Text>
          </View>
        </View>
      )}
    </View>
  );
}

function createStyles(colors: ThemeColors) {
  return StyleSheet.create({
    container: {
      backgroundColor: colors.surface,
      borderColor: colors.border,
      borderRadius: radius.md,
      borderWidth: 1,
      gap: spacing.sm,
      padding: spacing.md,
    },
    titleRow: {
      alignItems: 'center',
      flexDirection: 'row',
      gap: spacing.xs,
    },
    title: {
      color: colors.text,
      fontSize: 14,
      fontWeight: '700',
    },
    placeholder: {
      backgroundColor: colors.surface,
      borderColor: colors.border,
      borderRadius: radius.md,
      borderWidth: 1,
    },
    emptyContainer: {
      alignItems: 'center',
      justifyContent: 'center',
    },
    emptyText: {
      color: colors.textMuted,
      fontSize: 13,
    },
    summary: {
      flexDirection: 'row',
      gap: spacing.lg,
    },
    summaryItem: {
      gap: 2,
    },
    summaryLabel: {
      color: colors.textMuted,
      fontSize: 11,
    },
    summaryValue: {
      color: colors.text,
      fontSize: 14,
      fontWeight: '700',
    },
  });
}
