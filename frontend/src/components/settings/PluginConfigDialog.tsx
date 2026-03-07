'use client';

import { useEffect, useState } from 'react';
import { Plugin } from '@/lib/services/plugin-service';
import { PluginParameter, PluginSchemaService } from '@/lib/services/plugin-schema-service';
import { Dialog, DialogBody, DialogContent, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Badge } from '@/components/ui/badge';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { Switch } from '@/components/ui/switch';
import { TagInput } from '@/components/ui/tag-input';
import { useLanguage } from '@/contexts/LanguageContext';
import { AlertCircle } from 'lucide-react';

interface PluginConfigDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  plugin: Plugin | null;
  onConfigSaved?: () => void;
}

function hasConfiguredValue(value: unknown): boolean {
  if (value === undefined || value === null) return false;
  return typeof value !== 'string' || value !== '';
}

function parseBooleanValue(value: unknown): boolean {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number') return value !== 0;
  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase();
    if (['true', '1', 'yes', 'on'].includes(normalized)) return true;
    if (['false', '0', 'no', 'off', ''].includes(normalized)) return false;
  }
  return Boolean(value);
}

function normalizeArrayItems(items: string[]): string[] {
  const normalized = items.map(item => String(item ?? '').trim());
  const seen = new Set<string>();
  const result: string[] = [];

  normalized.forEach(item => {
    if (item === '') return;
    if (seen.has(item)) return;
    seen.add(item);
    result.push(item);
  });

  if (normalized.some(item => item === '')) {
    result.push('');
  }

  return result;
}

function parseArrayItems(value: unknown): string[] {
  if (Array.isArray(value)) {
    return normalizeArrayItems(value.map(item => String(item ?? '')));
  }

  const text = String(value ?? '').trim();
  if (!text) return [];

  try {
    const parsed = JSON.parse(text);
    if (!Array.isArray(parsed)) {
      throw new Error('Array parameters must use a JSON array.');
    }
    return normalizeArrayItems(parsed.map(item => String(item ?? '')));
  } catch (error) {
    if (text.startsWith('[')) {
      throw error instanceof Error ? error : new Error('Array parameters must use a JSON array.');
    }
  }

  return normalizeArrayItems(
    text
      .split(/[\n,]/)
      .map(item => item.trim())
      .filter(item => item.length > 0)
  );
}

function getInitialFieldValue(param: PluginParameter): any {
  const rawValue = hasConfiguredValue(param.value) ? param.value : param.default_value;

  switch (param.type) {
    case 'bool':
      return parseBooleanValue(rawValue);
    case 'array':
      return parseArrayItems(rawValue);
    case 'int':
      return rawValue ?? '';
    case 'string':
    default:
      return rawValue ?? '';
  }
}

function getPersistedFieldValue(param: PluginParameter, value: unknown): any {
  switch (param.type) {
    case 'bool':
      return parseBooleanValue(value);
    case 'array':
      return parseArrayItems(value);
    case 'int':
      return value !== undefined ? value : (param.default_value ?? '');
    case 'string':
    default:
      return value !== undefined ? value : (param.default_value ?? '');
  }
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

          const initialValues: Record<string, any> = {};
          pluginParameters.forEach((param: PluginParameter, index: number) => {
            initialValues[`param${index}`] = getInitialFieldValue(param);
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

  const handleSave = async () => {
    if (!plugin) return;

    try {
      setSaving(true);
      setSchemaError('');

      const updatedParameters = parameters.map((param, index) => {
        const paramName = `param${index}`;
        const value = formValues[paramName];

        return {
          name: param.name,
          type: param.type,
          desc: param.desc,
          default_value: param.default_value,
          value: getPersistedFieldValue(param, value)
        };
      });

      await PluginSchemaService.updatePluginConfigWithValidation(plugin.namespace, { parameters: updatedParameters });

      onOpenChange(false);
      onConfigSaved?.();
    } catch (error) {
      console.error('Failed to save config:', error);
      setSchemaError(error instanceof Error ? error.message : '保存插件参数失败');
    } finally {
      setSaving(false);
    }
  };

  const handleCancel = () => {
    onOpenChange(false);
  };

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
          {schemaError && (
            <Alert variant="destructive">
              <AlertCircle className="h-4 w-4" />
              <AlertDescription>{schemaError}</AlertDescription>
            </Alert>
          )}

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
                      <label className="text-sm font-medium">{param.desc}</label>
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
                                  placeholder={String(param.default_value || '')}
                                />
                              );
                            }
                            return (
                              <Input
                                type="text"
                                value={value || ''}
                                onChange={(e) => handleFieldChange(paramName, e.target.value)}
                                placeholder={String(param.default_value || '')}
                              />
                            );

                          case 'int':
                            return (
                              <Input
                                type="number"
                                value={value ?? ''}
                                onChange={(e) => handleFieldChange(paramName, e.target.value)}
                                placeholder={String(param.default_value || '')}
                              />
                            );

                          case 'bool':
                            return (
                              <div className="flex items-center gap-2">
                                <Switch
                                  checked={parseBooleanValue(value)}
                                  onCheckedChange={(checked) => handleFieldChange(paramName, checked)}
                                />
                                <span className="text-sm text-muted-foreground">
                                  {parseBooleanValue(value) ? t('settings.enabled') : t('settings.disabled')}
                                </span>
                              </div>
                            );

                          case 'array': {
                            const arrayValue = parseArrayItems(value);

                            return (
                              <div className="space-y-2">
                                <TagInput
                                  value={arrayValue}
                                  onChange={(nextTags) => handleFieldChange(paramName, nextTags)}
                                  placeholder="输入后按回车添加；直接回车添加空项"
                                  enableAutocomplete={false}
                                  allowEmpty={true}
                                  disabled={saving}
                                />
                                <span className="text-xs text-muted-foreground">
                                  按回车添加项目，输入内容后回车添加普通项，直接回车添加空项。点击标签上的 × 删除。
                                </span>
                              </div>
                            );
                          }

                          default:
                            return (
                              <Input
                                type="text"
                                value={value || ''}
                                onChange={(e) => handleFieldChange(paramName, e.target.value)}
                                placeholder={String(param.default_value || '')}
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
