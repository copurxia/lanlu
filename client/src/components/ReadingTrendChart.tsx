import React, {useCallback, useMemo, useState} from 'react';
import {LayoutChangeEvent, StyleSheet, Text, View} from 'react-native';
import Svg, {Circle, Line, Polyline, Text as SvgText} from 'react-native-svg';
import {TrendingUp} from 'lucide-react-native';
import {useTheme} from '../theme/ThemeContext';
import {useI18n} from '../i18n';
import {spacing, radius, type ThemeColors} from '../theme/colors';

type DataPoint = {
  date: string;
  count: number;
};

const CHART_HEIGHT = 200;
const PADDING = {top: 20, right: 20, bottom: 30, left: 40};

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

  const {points, yMax, xLabels, yLabels} = useMemo(() => {
    if (data.length === 0) {
      return {points: '', yMax: 5, xLabels: [] as {x: number; label: string}[], yLabels: [] as {y: number; label: string}[]};
    }
    const maxVal = Math.max(...data.map(d => d.count), 5);
    const xScale = chartWidth / Math.max(data.length - 1, 1);
    const yScale = chartHeight / maxVal;

    const pts = data.map((d, i) => {
      const x = PADDING.left + i * xScale;
      const y = PADDING.top + chartHeight - d.count * yScale;
      return `${x},${y}`;
    }).join(' ');

    const xLbls = data.map((d, i) => ({
      x: PADDING.left + i * xScale,
      label: formatDate(d.date),
    }));

    const steps = 4;
    const yLbls = Array.from({length: steps + 1}, (_, i) => {
      const val = Math.round((maxVal / steps) * i);
      return {
        y: PADDING.top + chartHeight - (val / maxVal) * chartHeight,
        label: String(val),
      };
    });

    return {points: pts, yMax: maxVal, xLabels: xLbls, yLabels: yLbls};
  }, [data, chartWidth, chartHeight]);

  const summary = useMemo(() => {
    if (data.length === 0) return null;
    let maxCount = 0;
    let maxDate = '';
    let daysWithReads = 0;
    for (const d of data) {
      if (d.count > maxCount) {
        maxCount = d.count;
        maxDate = d.date;
      }
      if (d.count > 0) daysWithReads++;
    }
    return {maxDate: formatDate(maxDate), maxCount, daysWithReads};
  }, [data]);

  if (loading) {
    return <View style={[styles.placeholder, {height: CHART_HEIGHT}]} />;
  }

  return (
    <View style={styles.container}>
      <View style={styles.titleRow}>
        <TrendingUp color={colors.text} size={18} />
        <Text style={styles.title}>{t('dashboard.readingTrend' as any)}</Text>
      </View>
      {data.length === 0 ? (
        <View style={[styles.emptyContainer, {height: CHART_HEIGHT}]}>
          <Text style={styles.emptyText}>{t('dashboard.noTrendData' as any)}</Text>
        </View>
      ) : (
        <View onLayout={onLayout}>
          {containerWidth > 0 && (
            <Svg width={containerWidth} height={CHART_HEIGHT}>
              {yLabels.map((yl, i) => (
                <React.Fragment key={`y-${i}`}>
                  <Line
                    x1={PADDING.left}
                    y1={yl.y}
                    x2={containerWidth - PADDING.right}
                    y2={yl.y}
                    stroke={colors.border}
                    strokeWidth={1}
                  />
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
              <Polyline
                points={points}
                fill="none"
                stroke={colors.primary}
                strokeWidth={2}
                strokeLinejoin="round"
                strokeLinecap="round"
              />
              {data.map((d, i) => {
                const xScale = chartWidth / Math.max(data.length - 1, 1);
                const yScale = chartHeight / yMax;
                const cx = PADDING.left + i * xScale;
                const cy = PADDING.top + chartHeight - d.count * yScale;
                return (
                  <Circle
                    key={`dot-${i}`}
                    cx={cx}
                    cy={cy}
                    r={3}
                    fill={colors.primary}
                  />
                );
              })}
            </Svg>
          )}
        </View>
      )}
      {summary && (
        <View style={styles.summary}>
          <View style={styles.summaryItem}>
            <Text style={styles.summaryLabel}>{t('dashboard.mostActiveDay' as any)}</Text>
            <Text style={styles.summaryValue}>{summary.maxDate}</Text>
          </View>
          <View style={styles.summaryItem}>
            <Text style={styles.summaryLabel}>{t('dashboard.daysWithReads' as any)}</Text>
            <Text style={styles.summaryValue}>{summary.daysWithReads}</Text>
          </View>
          <View style={styles.summaryItem}>
            <Text style={styles.summaryLabel}>{t('dashboard.readCount' as any)}</Text>
            <Text style={styles.summaryValue}>{summary.maxCount}</Text>
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
