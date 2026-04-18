'use client';

import { useState, useCallback, useEffect, useRef } from 'react';
import { Card, CardContent } from '@/components/ui/card';
import { logger } from '@/lib/utils/logger';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Settings, Save, RefreshCw } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { useLanguage } from '@/contexts/LanguageContext';
import { useAuth } from '@/contexts/AuthContext';
import { useDebounceCallback } from '@/hooks/common-hooks';
import { SystemSetting } from '@/lib/services/system-settings-api';

interface SettingsByCategory {
  [category: string]: SystemSetting[];
}

// 提取通用本地化函数到独立文件
const getLocalizedDescription = (description: Record<string, string> | string, currentLang: string): string => {
  // 如果已经是对象，直接查找
  if (typeof description === 'object' && description !== null) {
    return description[currentLang] || description['zh'] || description['en'] || '';
  }

  // 如果是字符串，尝试解析
  if (typeof description === 'string') {
    try {
      const descObj = JSON.parse(description);
      return descObj[currentLang] || descObj['zh'] || descObj['en'] || description;
    } catch {
      return description;
    }
  }

  return '';
};

export default function SystemSettingsPage() {
  const { t, language } = useLanguage();
  const { isAuthenticated } = useAuth();
  const { error: showError, success: showSuccess } = useToast();

  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [settings, setSettings] = useState<SettingsByCategory>({} as SettingsByCategory);
  const [activeTab, setActiveTab] = useState('storage');

  const categories = [
    { id: 'storage', name: t('settings.system.storage'), icon: '📁' },
    { id: 'performance', name: t('settings.system.performance'), icon: '⚡' },
    { id: 'server', name: t('settings.system.server'), icon: '🖥️' },
    { id: 'ssl', name: t('settings.system.ssl'), icon: '🔒' },
  ];

  // 使用 useRef 稳定函数引用，避免 useEffect 无限循环
  const tRef = useRef(t);
  const showErrorRef = useRef(showError);

  useEffect(() => {
    tRef.current = t;
    showErrorRef.current = showError;
  }, [t, showError]);

  const loadSettings = useCallback(async () => {
    try {
      setLoading(true);
      const response = await fetch('/api/admin/system/settings');
      const data = await response.json();

      if (data.success) {
        const grouped = groupSettingsByCategory(data.data);
        setSettings(grouped);
      } else {
        showErrorRef.current?.(data.message || tRef.current('settings.system.loadError'));
      }
    } catch (error) {
      logger.apiError('load system settings', error as Error);
      showErrorRef.current?.(tRef.current('settings.system.loadError'));
    } finally {
      setLoading(false);
    }
  }, []);

  // 使用防抖避免频繁调用
  const debouncedLoadSettings = useDebounceCallback(loadSettings, 300);

  // 初始加载 - 只在 isAuthenticated 变化时执行一次
  useEffect(() => {
    if (typeof window !== 'undefined' && isAuthenticated) {
      debouncedLoadSettings();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isAuthenticated]);

  const groupSettingsByCategory = (settings: SystemSetting[]): SettingsByCategory => {
    const grouped: SettingsByCategory = {};
    settings.forEach(setting => {
      if (!grouped[setting.category]) {
        grouped[setting.category] = [];
      }
      grouped[setting.category].push(setting);
    });
    return grouped;
  };

  const handleValueChange = (category: string, key: string, value: string) => {
    setSettings(prev => ({
      ...prev,
      [category]: (prev[category] || []).map(setting =>
        setting.key === key ? { ...setting, value } : setting
      ),
    }));
  };

  const handleSave = async (category: string) => {
    try {
      setSaving(true);
      const categorySettings = settings[category] || [];

      const updates = categorySettings.map(setting => ({
        key: setting.key,
        value: setting.value,
      }));

      const response = await fetch('/api/admin/system/settings/batch', {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          settings: updates.reduce((acc, item) => {
            acc[item.key] = item.value;
            return acc;
          }, {} as Record<string, string>),
        }),
      });

      const data = await response.json();

      if (data.success) {
        showSuccess(t('settings.system.saveSuccess'));
      } else {
        showError(data.message || t('settings.system.saveError'));
      }
    } catch (error) {
      logger.apiError('save system settings', error);
      showError(t('settings.system.saveError'));
    } finally {
      setSaving(false);
    }
  };

  const renderSettingInput = (setting: SystemSetting) => {
    const { key, value, valueType, description } = setting;
    // 使用LanguageContext中的language
    const currentLang = language;
    // 解析本地化描述
    const localizedDesc = getLocalizedDescription(description, currentLang);

    switch (valueType) {
      case 'boolean':
        return (
          <div className="flex items-center space-x-2">
            <Switch
              checked={value === 'true'}
              onCheckedChange={(checked) =>
                handleValueChange(setting.category, key, checked.toString())
              }
            />
            <span className="text-sm text-muted-foreground">{localizedDesc}</span>
          </div>
        );

      case 'integer':
        return (
          <div className="space-y-2">
            <Label htmlFor={key}>{localizedDesc}</Label>
            <Input
              id={key}
              type="number"
              value={value}
              onChange={(e) =>
                handleValueChange(setting.category, key, e.target.value)
              }
            />
          </div>
        );

      case 'long':
        return (
          <div className="space-y-2">
            <Label htmlFor={key}>{localizedDesc}</Label>
            <Input
              id={key}
              type="number"
              value={value}
              onChange={(e) =>
                handleValueChange(setting.category, key, e.target.value)
              }
            />
            <p className="text-xs text-muted-foreground">
              {t('settings.system.longHint')}
            </p>
          </div>
        );

      case 'path':
        return (
          <div className="space-y-2">
            <Label htmlFor={key}>{localizedDesc}</Label>
            <Input
              id={key}
              type="text"
              value={value}
              onChange={(e) =>
                handleValueChange(setting.category, key, e.target.value)
              }
              placeholder={t('settings.system.pathPlaceholder')}
            />
          </div>
        );

      default:
        return (
          <div className="space-y-2">
            <Label htmlFor={key}>{localizedDesc}</Label>
            <Input
              id={key}
              type="text"
              value={value}
              onChange={(e) =>
                handleValueChange(setting.category, key, e.target.value)
              }
            />
          </div>
        );
    }
  };

  if (!isAuthenticated) {
    return (
      <div className="flex items-center justify-center h-64">
        <p className="text-muted-foreground">{t('common.unauthorized')}</p>
      </div>
    );
  }

  if (loading) {
    return (
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div className="space-y-1">
            <h2 className="text-xl font-semibold flex items-center gap-2">
              <Settings className="w-5 h-5" />
              {t('settings.system.title')}
            </h2>
            <p className="text-sm text-muted-foreground">{t('settings.system.description')}</p>
          </div>
        </div>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-center h-64">
              <RefreshCw className="w-8 h-8 animate-spin text-muted-foreground" />
            </div>
          </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* 页面标题 */}
      <div className="flex items-center justify-between">
        <div className="space-y-1">
          <h2 className="text-xl font-semibold flex items-center gap-2">
            <Settings className="w-5 h-5" />
            {t('settings.system.title')}
          </h2>
          <p className="text-sm text-muted-foreground">{t('settings.system.description')}</p>
        </div>
      </div>

      {/* 设置选项卡 */}
      <Tabs value={activeTab} onValueChange={setActiveTab}>
        <TabsList
          className="grid w-full mb-4"
          style={{ gridTemplateColumns: `repeat(${categories.length}, minmax(0, 1fr))` }}
        >
          {categories.map((category) => (
            <TabsTrigger key={category.id} value={category.id}>
              <span className="mr-2">{category.icon}</span>
              {category.name}
            </TabsTrigger>
          ))}
        </TabsList>

        {categories.map((category) => (
          <TabsContent key={category.id} value={category.id} className="mt-6">
            <Card>
              <CardContent className="p-6 space-y-6">
                {category.id === 'ssl' && (
                  <div className="rounded-lg border border-border/60 bg-muted/30 p-4 text-sm text-muted-foreground">
                    <p>{t('settings.system.sslNotice')}</p>
                    <p className="mt-2">{t('settings.system.sslRestartHint')}</p>
                  </div>
                )}

                {category.id === 'performance' && (
                  <div className="rounded-lg border border-border/60 bg-muted/30 p-4 text-sm text-muted-foreground">
                    <p>{t('settings.system.performanceNotice')}</p>
                    <p className="mt-2">{t('settings.system.performanceRestartHint')}</p>
                  </div>
                )}

                {settings[category.id]?.map((setting) => (
                  <div key={setting.key}>
                    {renderSettingInput(setting)}
                  </div>
                ))}

                {settings[category.id] && settings[category.id].length > 0 && (
                  <div className="flex justify-end">
                    <Button
                      onClick={() => handleSave(category.id)}
                      disabled={saving}
                      className="flex items-center gap-2"
                    >
                      <Save className="w-4 h-4" />
                      {saving ? t('common.saving') : t('common.save')}
                    </Button>
                  </div>
                )}
              </CardContent>
            </Card>
          </TabsContent>
        ))}
      </Tabs>
    </div>
  );
}
