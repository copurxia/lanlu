'use client';

import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { TrendingUp } from 'lucide-react';
import { useLanguage } from '@/contexts/LanguageContext';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';
import { ReadingTrendItem } from '@/lib/user-stats-service';

interface ReadingTrendChartProps {
  data: ReadingTrendItem[];
  loading?: boolean;
}

export function ReadingTrendChart({ data, loading = false }: ReadingTrendChartProps) {
  const { t } = useLanguage();

  if (loading) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <TrendingUp className="w-5 h-5" />
            <Skeleton className="h-5 w-24" />
          </CardTitle>
        </CardHeader>
        <CardContent>
          <Skeleton className="h-[200px] w-full" />
        </CardContent>
      </Card>
    );
  }

  // 格式化日期显示
  const formatDate = (dateStr: string) => {
    if (!dateStr) return '';
    const date = new Date(dateStr);
    return date.toLocaleDateString('zh-CN', { month: 'short', day: 'numeric' });
  };

  // 格式化X轴标签（稀疏显示，避免拥挤）
  const formatXAxisTick = (dateStr: string) => {
    const date = new Date(dateStr);
    return `${date.getMonth() + 1}/${date.getDate()}`;
  };

  // 计算总阅读量
  const totalReads = data.reduce((sum, item) => sum + item.count, 0);

  // 计算平均阅读量
  const avgReads = data.length > 0 ? Math.round(totalReads / data.length * 10) / 10 : 0;

  // 使用useMemo创建稳定的tooltip函数
  const tooltipContent = (props: any) => {
    const { active, payload, label } = props;
    if (active && payload && payload.length) {
      return (
        <div className="bg-background border border-border rounded-lg p-2 shadow-lg">
          <p className="text-sm font-medium">{formatDate(label)}</p>
          <p className="text-sm text-primary">
            {t('dashboard.readCount')}: <span className="font-semibold">{payload[0].value}</span>
          </p>
        </div>
      );
    }
    return null;
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <TrendingUp className="w-5 h-5" />
          {t('dashboard.readingTrend')}
        </CardTitle>
        {data.length > 0 && (
          <div className="text-sm text-muted-foreground">
            {t('dashboard.lastNDays', { days: data.length })} · {t('dashboard.totalRead')}: {totalReads} · {t('dashboard.avgRead')}: {avgReads}
          </div>
        )}
      </CardHeader>
      <CardContent>
        {data.length > 0 ? (
          <>
            <ResponsiveContainer width="100%" height={200}>
              <LineChart
                data={data}
                margin={{ top: 10, right: 20, left: 0, bottom: 20 }}
              >
                <CartesianGrid strokeDasharray="3 3" className="stroke-muted" />
                <XAxis
                  dataKey="date"
                  tickFormatter={formatXAxisTick}
                  className="text-xs"
                  tick={{ fill: 'hsl(var(--muted-foreground))' }}
                  interval="preserveStartEnd"
                  angle={-45}
                  textAnchor="end"
                  height={60}
                />
                <YAxis
                  allowDecimals={false}
                  className="text-xs"
                  tick={{ fill: 'hsl(var(--muted-foreground))' }}
                />
                <Tooltip content={tooltipContent} />
                <Line
                  type="monotone"
                  dataKey="count"
                  stroke="hsl(var(--primary))"
                  strokeWidth={2}
                  dot={{ fill: 'hsl(var(--primary))', r: 3 }}
                  activeDot={{ r: 5 }}
                  name={t('dashboard.readCount')}
                />
              </LineChart>
            </ResponsiveContainer>

            {/* 统计信息 */}
            <div className="mt-4 flex items-center justify-between">
              {/* 趋势分析 */}
              <div className="text-xs text-muted-foreground">
                <span>{t('dashboard.mostActiveDay')}: {data.reduce((max, item) => item.count > max.count ? item : max, { date: '', count: 0 }).count > 0 ? formatDate(data.reduce((max, item) => item.count > max.count ? item : max, { date: '', count: 0 }).date) : t('dashboard.none')}</span>
                <span className="ml-3">{t('dashboard.daysWithReads')}: {data.filter(item => item.count > 0).length}/{data.length}</span>
              </div>

              {/* 最高阅读量 */}
              <div className="text-xs text-muted-foreground">
                Max: {Math.max(...data.map(item => item.count))}
              </div>
            </div>
          </>
        ) : (
          <div className="h-[200px] flex items-center justify-center text-muted-foreground">
            {t('dashboard.noTrendData')}
          </div>
        )}
      </CardContent>
    </Card>
  );
}
