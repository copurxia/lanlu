/**
 * 按时间分组工具函数
 * 支持按今天、昨天、三天前、一周前、更早分组
 */

export interface TimeGroup {
  label: string;
  archives: any[];
}

/**
 * 根据时间戳将档案分组
 * @param archives 档案列表
 * @param timeField 时间字段名（默认为 'last_read_time'）
 * @param t 翻译函数
 * @returns 分组后的对象
 */
export function groupArchivesByTime(archives: any[], timeField: string = 'last_read_time', t?: (key: string) => string): TimeGroup[] {
  // 使用用户的本地时间
  const now = new Date();
  // 获取今天的开始时间（本地时区00:00:00）
  const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  // 昨天的开始时间
  const yesterdayStart = new Date(todayStart.getTime() - 24 * 60 * 60 * 1000);
  // 3天前的开始时间
  const threeDaysStart = new Date(todayStart.getTime() - 3 * 24 * 60 * 60 * 1000);
  // 7天前的开始时间
  const weekStart = new Date(todayStart.getTime() - 7 * 24 * 60 * 60 * 1000);

  // 初始化分组
  const groups: { [key: string]: any[] } = {
    'today': [],
    'yesterday': [],
    'threeDaysAgo': [],
    'weekAgo': [],
    'older': []
  };

  // 分组逻辑
  archives.forEach(archive => {
    const timeValue = archive[timeField];
    if (!timeValue) {
      groups['older'].push(archive);
      return;
    }

    // 解析时间值（支持字符串格式的日期时间或时间戳）
    let archiveDate: Date;
    if (typeof timeValue === 'string') {
      // 字符串格式的日期时间，如 "2025-12-16 10:20:56.870451"
      archiveDate = new Date(timeValue);
    } else if (typeof timeValue === 'number') {
      // 时间戳（秒）
      archiveDate = new Date(timeValue * 1000);
    } else {
      // 未知格式，放入"更早"分组
      groups['older'].push(archive);
      return;
    }

    // 检查日期是否有效
    if (isNaN(archiveDate.getTime())) {
      groups['older'].push(archive);
      return;
    }

    // 按本地时间范围分组
    if (archiveDate >= todayStart) {
      groups['today'].push(archive);
    } else if (archiveDate >= yesterdayStart) {
      groups['yesterday'].push(archive);
    } else if (archiveDate >= threeDaysStart) {
      groups['threeDaysAgo'].push(archive);
    } else if (archiveDate >= weekStart) {
      groups['weekAgo'].push(archive);
    } else {
      groups['older'].push(archive);
    }
  });

  // 转换为数组格式，只包含非空分组
  const result: TimeGroup[] = [];
  
  // 使用翻译函数或默认中文标签
  const labelMap: { [K in keyof typeof groups]: string } = {
    'today': t ? t('common.today') : '今天',
    'yesterday': t ? t('common.yesterday') : '昨天',
    'threeDaysAgo': t ? t('common.threeDaysAgo') : '三天前',
    'weekAgo': t ? t('common.weekAgo') : '一周前',
    'older': t ? t('common.older') : '更早'
  };

  (Object.keys(groups) as Array<keyof typeof groups>).forEach(key => {
    if (groups[key].length > 0) {
      result.push({
        label: labelMap[key],
        archives: groups[key]
      });
    }
  });

  return result;
}

/**
 * 格式化时间显示
 * @param timestamp 时间戳（秒）
 * @param t 翻译函数
 * @returns 格式化的时间字符串
 */
export function formatTime(timestamp: number, t?: (key: string) => string): string {
  if (!timestamp) return '';

  const date = new Date(timestamp * 1000);
  const now = new Date();
  const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());

  if (date >= todayStart) {
    // 今天，只显示时间
    return date.toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' });
  }

  const yesterdayStart = new Date(todayStart.getTime() - 24 * 60 * 60 * 1000);
  if (date >= yesterdayStart) {
    return t ? t('common.yesterday') : '昨天';
  }

  const threeDaysStart = new Date(todayStart.getTime() - 3 * 24 * 60 * 60 * 1000);
  if (date >= threeDaysStart) {
    return t ? t('common.threeDaysAgo') : '三天内';
  }

  const weekStart = new Date(todayStart.getTime() - 7 * 24 * 60 * 60 * 1000);
  if (date >= weekStart) {
    return t ? t('common.weekAgo') : '一周内';
  }

  // 更早的日期，显示月-日
  return date.toLocaleDateString('zh-CN', { month: '2-digit', day: '2-digit' });
}