'use client';

import { useState, useEffect } from 'react';
import { Plugin } from '@/lib/plugin-service';
import { PluginSchemaService, PluginParameter } from '@/lib/plugin-schema-service';
import { Dialog, DialogBody, DialogContent, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Badge } from '@/components/ui/badge';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { Switch } from '@/components/ui/switch';
import { useLanguage } from '@/contexts/LanguageContext';
import { AlertCircle } from 'lucide-react';

interface PluginConfigDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  plugin: Plugin | null;
  onConfigSaved?: () => void;
}

export function PluginConfigDialog({
  open,
  onOpenChange,
  plugin,
  onConfigSaved
}: PluginConfigDialogProps) {
  const { t } = useLanguage();
  const [saving, setSaving] = useState(false);
  const [parameters, setParameters] = useState<PluginParameter[]>([]);
  const [formValues, setFormValues] = useState<Record<string, any>>({});
  const [loadingSchema, setLoadingSchema] = useState(false);
  const [schemaError, setSchemaError] = useState<string>('');

  useEffect(() => {
    const loadPluginSchema = async () => {
      if (!plugin) return;

      setLoadingSchema(true);
      setSchemaError('');

      try {
        const schemaResponse = await PluginSchemaService.getPluginSchema(plugin.namespace);

        if (schemaResponse.has_schema && schemaResponse.parameters) {
          // 解析parameters字符串为数组
          let pluginParameters: PluginParameter[] = [];
          if (typeof schemaResponse.parameters === 'string') {
            try {
              pluginParameters = JSON.parse(schemaResponse.parameters);
            } catch (e) {
              console.error('Failed to parse parameters JSON:', e);
            }
          } else {
            pluginParameters = schemaResponse.parameters;
          }

          setParameters(pluginParameters);

          // 从parameters数组中的value字段创建初始值
          const initialValues: Record<string, any> = {};
          pluginParameters.forEach((param: PluginParameter, index: number) => {
            const paramName = `param${index}`;

            // 优先使用parameters中的value字段
            if (param.value !== undefined && param.value !== null && param.value !== '') {
              initialValues[paramName] = param.value;
            } else if (param.default_value !== undefined) {
              initialValues[paramName] = param.default_value;
            } else if (param.type === 'bool') {
              initialValues[paramName] = false;
            } else {
              initialValues[paramName] = '';
            }
          });

          setFormValues(initialValues);
          setSchemaError('');
        } else {
          setParameters([]);
          setSchemaError(schemaResponse.message || '插件不支持参数配置');
        }
      } catch (error) {
        console.error('Failed to load plugin schema:', error);
        setSchemaError('加载插件参数失败');
      } finally {
        setLoadingSchema(false);
      }
    };

    if (plugin) {
      loadPluginSchema();
    }
  }, [plugin]);

  // 保存插件配置
  const handleSave = async () => {
    if (!plugin) return;

    try {
      setSaving(true);

      // 构建完整的parameters数组，包含用户编辑的value
      const updatedParameters = parameters.map((param, index) => {
        const paramName = `param${index}`;
        const value = formValues[paramName];

        return {
          name: param.name,
          type: param.type,
          desc: param.desc,
          default_value: param.default_value,
          value: value !== undefined ? value : (param.default_value || '')
        };
      });

      // 使用带验证的API保存配置，发送parameters数组
      await PluginSchemaService.updatePluginConfigWithValidation(plugin.namespace, { parameters: updatedParameters });

      onOpenChange(false);
      onConfigSaved?.();
    } catch (error) {
      console.error('Failed to save config:', error);
      // 可以在这里显示错误提示
    } finally {
      setSaving(false);
    }
  };

  const handleCancel = () => {
    onOpenChange(false);
  };

  // 字段值变更处理
  const handleFieldChange = (paramName: string, value: any) => {
    setFormValues(prev => ({
      ...prev,
      [paramName]: value
    }));
  };

  if (!plugin) return null;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent size="xl">
        <DialogBody className="space-y-4">
          {/* 错误提示 */}
          {schemaError && (
            <Alert variant="destructive">
              <AlertCircle className="h-4 w-4" />
              <AlertDescription>{schemaError}</AlertDescription>
            </Alert>
          )}

          {/* 参数表单 */}
          {loadingSchema ? (
            <div className="flex items-center justify-center py-16">
              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary"></div>
            </div>
          ) : parameters.length > 0 ? (
            <div className="space-y-4">
              {parameters.map((param, index) => {
                const paramName = `param${index}`;
                const value = formValues[paramName];

                return (
                  <div key={paramName} className="space-y-2">
                    <div className="flex items-center gap-2">
                      <label className="text-sm font-medium">
                        {param.desc}
                      </label>
                      <Badge variant="secondary" className="text-xs px-1 py-0">
                        {param.type}
                      </Badge>
                    </div>
                    <div>
                      {(() => {
                        switch (param.type) {
                          case 'string':
                            if (param.desc.includes('description') || param.desc.includes('comment')) {
                              return (
                                <Textarea
                                  value={value || ''}
                                  onChange={(e) => handleFieldChange(paramName, e.target.value)}
                                  rows={2}
                                  className="resize-none"
                                  placeholder={param.default_value || ''}
                                />
                              );
                            }
                            return (
                              <Input
                                type="text"
                                value={value || ''}
                                onChange={(e) => handleFieldChange(paramName, e.target.value)}
                                placeholder={param.default_value || ''}
                              />
                            );

                          case 'int':
                            return (
                              <Input
                                type="number"
                                value={value ?? ''}
                                onChange={(e) => handleFieldChange(paramName, e.target.value)}
                                placeholder={param.default_value || ''}
                              />
                            );

                          case 'bool':
                            return (
                              <div className="flex items-center gap-2">
                                <Switch
                                  checked={Boolean(value)}
                                  onCheckedChange={(checked) => handleFieldChange(paramName, checked)}
                                />
                                <span className="text-sm text-muted-foreground">
                                  {value ? t('settings.enabled') : t('settings.disabled')}
                                </span>
                              </div>
                            );

                          default:
                            return (
                              <Input
                                type="text"
                                value={value || ''}
                                onChange={(e) => handleFieldChange(paramName, e.target.value)}
                                placeholder={param.default_value || ''}
                              />
                            );
                        }
                      })()}
                    </div>
                  </div>
                );
              })}
            </div>
          ) : (
            <div className="text-center py-8 text-muted-foreground">
              {t('settings.noConfigurationRequired')}
            </div>
          )}
        </DialogBody>

        <DialogFooter>
          <Button variant="outline" onClick={handleCancel} disabled={saving}>
            {t('common.cancel')}
          </Button>
          <Button onClick={handleSave} disabled={saving || parameters.length === 0}>
            {saving ? t('common.saving') : t('common.save')}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
