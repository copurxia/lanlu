'use client';

import { useState, useEffect, useCallback, useRef } from 'react';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Settings, Save, RefreshCw } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { useLanguage } from '@/contexts/LanguageContext';
import { useAuth } from '@/contexts/AuthContext';
import { SystemSetting } from '@/lib/system-settings-api';

interface SettingsByCategory {
  [category: string]: SystemSetting[];
}

// 解析description对象并根据当前语言返回合适文本
const getLocalizedDescription = (description: Record<string, string> | string, currentLang: string): string => {
  try {
    // 如果description已经是对象，直接使用
    if (typeof description === 'object' && description !== null) {
      // 优先使用当前语言，如果没有则使用中文，最后使用英文
      return description[currentLang] || description['zh'] || description['en'] || '';
    }

    // 如果description是字符串，尝试解析JSON
    const descObj = JSON.parse(description);
    return descObj[currentLang] || descObj['zh'] || descObj['en'] || description;
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
  } catch (_error) {
    // 如果解析失败，返回原始字符串或空字符串
    return typeof description === 'string' ? description : '';
  }
};

export default function SystemSettingsPage() {
  const { t, language } = useLanguage();
  const { isAuthenticated } = useAuth();
  const { error: showError, success: showSuccess } = useToast();

  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [settings, setSettings] = useState<SettingsByCategory>({} as SettingsByCategory);
  const [activeTab, setActiveTab] = useState('storage');
  
  // 添加防抖计时器引用
  const loadSettingsTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const categories = [
    { id: 'storage', name: t('settings.system.storage'), icon: '📁' },
    { id: 'task', name: t('settings.system.task'), icon: '⏰' },
    { id: 'performance', name: t('settings.system.performance'), icon: '⚡' },
  ];

  const loadSettings = useCallback(() => {
    // 清除之前的定时器
    if (loadSettingsTimeoutRef.current) {
      clearTimeout(loadSettingsTimeoutRef.current);
    }
    
    // 设置新的定时器（防抖）
    loadSettingsTimeoutRef.current = setTimeout(async () => {
      try {
        setLoading(true);
        const response = await fetch('/api/system/settings');
        const data = await response.json();

        if (data.success) {
          const grouped = groupSettingsByCategory(data.data);
          setSettings(grouped);
        } else {
          showError(data.message || t('settings.system.loadError'));
        }
      } catch (error) {
        console.error(t('settings.system.loadError'), ':', error as Error);
        showError(t('settings.system.loadError'));
      } finally {
        setLoading(false);
      }
    }, 300); // 300ms 防抖延迟
  }, [t, showError]);

  useEffect(() => {
    if (typeof window !== 'undefined' && isAuthenticated) {
      loadSettings();
    }
    
    // 清理函数：在组件卸载时清除定时器
    return () => {
      if (loadSettingsTimeoutRef.current) {
        clearTimeout(loadSettingsTimeoutRef.current);
      }
    };
  }, [isAuthenticated]); // 移除了 loadSettings 依赖项，避免因 useCallback 依赖变化导致的重复调用

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

      const response = await fetch('/api/system/settings/batch', {
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
      console.error(t('settings.system.saveError'), ':', error);
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
        <TabsList className="grid grid-cols-3 w-full mb-4">
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
