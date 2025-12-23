'use client';

import { useState, useEffect } from 'react';
import { CheckCircle, XCircle, ChevronDown } from 'lucide-react';
import { useLanguage } from '@/contexts/LanguageContext';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { Badge } from '@/components/ui/badge';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogBody,
} from '@/components/ui/dialog';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from '@/components/ui/collapsible';
import { CronService, ScheduledTask, ScheduledTaskInput, CronValidationResult } from '@/lib/cron-service';
import { useToast } from '@/hooks/use-toast';

interface ScheduledTaskDialogProps {
  open: boolean;
  taskId: number | null;
  onClose: () => void;
  onSaved: () => void;
}

export function ScheduledTaskDialog({ open, taskId, onClose, onSaved }: ScheduledTaskDialogProps) {
  const { t } = useLanguage();
  const { success, error: toastError } = useToast();
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [validating, setValidating] = useState(false);
  const [validation, setValidation] = useState<CronValidationResult | null>(null);
  const [presetsOpen, setPresetsOpen] = useState(false);

  // Form state
  const [name, setName] = useState('');
  const [cronExpression, setCronExpression] = useState('');
  const [taskType, setTaskType] = useState('');
  const [taskParameters, setTaskParameters] = useState('');
  const [enabled, setEnabled] = useState(true);
  const [priority, setPriority] = useState(50);
  const [timeoutSeconds, setTimeoutSeconds] = useState(3600);

  const isEditing = taskId !== null;

  // Load task data when editing
  useEffect(() => {
    if (open && taskId !== null) {
      loadTask(taskId);
    } else if (open && taskId === null) {
      // Reset form for new task
      resetForm();
    }
  }, [open, taskId]);

  const resetForm = () => {
    setName('');
    setCronExpression('');
    setTaskType('');
    setTaskParameters('');
    setEnabled(true);
    setPriority(50);
    setTimeoutSeconds(3600);
    setValidation(null);
  };

  const loadTask = async (id: number) => {
    setLoading(true);
    try {
      const task = await CronService.getTask(id);
      if (task) {
        setName(task.name);
        setCronExpression(task.cronExpression);
        setTaskType(task.taskType);
        // 确保 taskParameters 是字符串
        const params = task.taskParameters;
        if (typeof params === 'object' && params !== null) {
          setTaskParameters(JSON.stringify(params, null, 2));
        } else {
          setTaskParameters(params || '');
        }
        setEnabled(task.enabled);
        setPriority(task.priority);
        setTimeoutSeconds(task.timeoutSeconds);
      }
    } catch (e) {
      console.error('Failed to load task:', e);
    } finally {
      setLoading(false);
    }
  };

  const handleValidate = async () => {
    if (!cronExpression.trim()) return;
    setValidating(true);
    try {
      const result = await CronService.validateExpression(cronExpression);
      setValidation(result);
    } catch (e) {
      console.error('Failed to validate expression:', e);
    } finally {
      setValidating(false);
    }
  };

  const handlePresetSelect = (value: string) => {
    setCronExpression(value);
    setValidation(null);
    setPresetsOpen(false);
  };

  const handleSave = async () => {
    if (!name.trim() || !cronExpression.trim() || !taskType) {
      toastError(t('common.required'));
      return;
    }

    setSaving(true);
    try {
      const input: ScheduledTaskInput = {
        name: name.trim(),
        cronExpression: cronExpression.trim(),
        taskType,
        taskParameters: taskParameters.trim() || undefined,
        enabled,
        priority,
        timeoutSeconds,
      };

      if (isEditing && taskId !== null) {
        const result = await CronService.updateTask(taskId, input);
        if (result.success) {
          success(t('settings.cronManagement.updateSuccess'));
          onSaved();
        } else {
          toastError(result.error || t('settings.cronManagement.updateFailed'));
        }
      } else {
        const result = await CronService.createTask(input);
        if (result.success) {
          success(t('settings.cronManagement.createSuccess'));
          onSaved();
        } else {
          toastError(result.error || t('settings.cronManagement.createFailed'));
        }
      }
    } catch (e) {
      console.error('Failed to save task:', e);
      toastError(isEditing ? t('settings.cronManagement.updateFailed') : t('settings.cronManagement.createFailed'));
    } finally {
      setSaving(false);
    }
  };

  const getTaskTypeLabel = (type: string) => {
    const key = `settings.cronManagement.taskTypes.${type}`;
    const translated = t(key);
    return translated !== key ? translated : type;
  };

  const getTaskTypeDesc = (type: string) => {
    const key = `settings.cronManagement.taskTypes.${type}Desc`;
    const translated = t(key);
    return translated !== key ? translated : '';
  };

  return (
    <Dialog open={open} onOpenChange={onClose}>
      <DialogContent size="md">
        <DialogHeader>
          <DialogTitle>
            {isEditing ? t('settings.cronManagement.editTask') : t('settings.cronManagement.createTask')}
          </DialogTitle>
          <DialogDescription>
            {t('settings.cronManagement.description')}
          </DialogDescription>
        </DialogHeader>

        <DialogBody>
          {loading ? (
            <div className="py-8 text-center text-muted-foreground">
              {t('common.loading')}
            </div>
          ) : (
            <div className="space-y-4">
              {/* Task Name */}
              <div className="space-y-2">
                <Label htmlFor="name">{t('settings.cronManagement.taskName')} *</Label>
                <Input
                  id="name"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  placeholder={t('settings.cronManagement.taskNamePlaceholder')}
                />
              </div>

              {/* Task Type */}
              <div className="space-y-2">
                <Label htmlFor="taskType">{t('settings.cronManagement.taskType')} *</Label>
                <Select value={taskType} onValueChange={setTaskType}>
                  <SelectTrigger>
                    <SelectValue placeholder={t('settings.cronManagement.taskTypePlaceholder')} />
                  </SelectTrigger>
                  <SelectContent>
                    {CronService.TASK_TYPES.map((type) => (
                      <SelectItem key={type.value} value={type.value}>
                        <div>
                          <div>{getTaskTypeLabel(type.value)}</div>
                          <div className="text-xs text-muted-foreground">{getTaskTypeDesc(type.value)}</div>
                        </div>
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>

              {/* Cron Expression */}
              <div className="space-y-2">
                <Label htmlFor="cronExpression">{t('settings.cronManagement.cronExpression')} *</Label>
                <div className="flex gap-2">
                  <Input
                    id="cronExpression"
                    value={cronExpression}
                    onChange={(e) => {
                      setCronExpression(e.target.value);
                      setValidation(null);
                    }}
                    placeholder={t('settings.cronManagement.cronExpressionPlaceholder')}
                    className="flex-1"
                  />
                  <Button
                    type="button"
                    variant="outline"
                    onClick={handleValidate}
                    disabled={validating || !cronExpression.trim()}
                  >
                    {validating ? '...' : t('settings.cronManagement.validateExpression')}
                  </Button>
                </div>
                <p className="text-xs text-muted-foreground">{t('settings.cronManagement.cronExpressionHelp')}</p>

                {/* Validation Result */}
                {validation && (
                  <div className={`p-2 rounded text-sm ${validation.valid ? 'bg-green-50 dark:bg-green-950' : 'bg-red-50 dark:bg-red-950'}`}>
                    <div className="flex items-center gap-2">
                      {validation.valid ? (
                        <CheckCircle className="w-4 h-4 text-green-500" />
                      ) : (
                        <XCircle className="w-4 h-4 text-red-500" />
                      )}
                      <span>
                        {validation.valid
                          ? t('settings.cronManagement.expressionValid')
                          : `${t('settings.cronManagement.expressionInvalid')}: ${validation.error}`}
                      </span>
                    </div>
                    {validation.valid && validation.nextRuns.length > 0 && (
                      <div className="mt-2">
                        <p className="text-xs text-muted-foreground mb-1">{t('settings.cronManagement.nextRunTimes')}:</p>
                        <div className="space-y-0.5">
                          {validation.nextRuns.slice(0, 3).map((time, i) => (
                            <div key={i} className="text-xs">{time}</div>
                          ))}
                        </div>
                      </div>
                    )}
                  </div>
                )}

                {/* Presets */}
                <Collapsible open={presetsOpen} onOpenChange={setPresetsOpen}>
                  <CollapsibleTrigger asChild>
                    <Button variant="ghost" size="sm" className="w-full justify-between">
                      {t('settings.cronManagement.cronPresets')}
                      <ChevronDown className={`w-4 h-4 transition-transform ${presetsOpen ? 'rotate-180' : ''}`} />
                    </Button>
                  </CollapsibleTrigger>
                  <CollapsibleContent className="pt-2">
                    <div className="flex flex-wrap gap-2">
                      {CronService.CRON_PRESETS.map((preset) => (
                        <Badge
                          key={preset.value}
                          variant="outline"
                          className="cursor-pointer hover:bg-accent"
                          onClick={() => handlePresetSelect(preset.value)}
                        >
                          {preset.label} ({preset.value})
                        </Badge>
                      ))}
                    </div>
                  </CollapsibleContent>
                </Collapsible>
              </div>

              {/* Task Parameters */}
              <div className="space-y-2">
                <Label htmlFor="taskParameters">{t('settings.cronManagement.taskParameters')}</Label>
                <Textarea
                  id="taskParameters"
                  value={taskParameters}
                  onChange={(e) => setTaskParameters(e.target.value)}
                  placeholder={t('settings.cronManagement.taskParametersPlaceholder')}
                  rows={2}
                />
              </div>

              {/* Priority */}
              <div className="space-y-2">
                <Label htmlFor="priority">{t('settings.cronManagement.priority')}</Label>
                <Input
                  id="priority"
                  type="number"
                  min={1}
                  max={100}
                  value={priority}
                  onChange={(e) => setPriority(parseInt(e.target.value) || 50)}
                />
                <p className="text-xs text-muted-foreground">{t('settings.cronManagement.priorityHelp')}</p>
              </div>

              {/* Timeout */}
              <div className="space-y-2">
                <Label htmlFor="timeoutSeconds">{t('settings.cronManagement.timeoutSeconds')}</Label>
                <Input
                  id="timeoutSeconds"
                  type="number"
                  min={60}
                  max={86400}
                  value={timeoutSeconds}
                  onChange={(e) => setTimeoutSeconds(parseInt(e.target.value) || 3600)}
                />
                <p className="text-xs text-muted-foreground">{t('settings.cronManagement.timeoutSecondsHelp')}</p>
              </div>

              {/* Enabled */}
              <div className="flex items-center justify-between">
                <Label htmlFor="enabled">{t('settings.cronManagement.enabled')}</Label>
                <Switch
                  id="enabled"
                  checked={enabled}
                  onCheckedChange={setEnabled}
                />
              </div>
            </div>
          )}
        </DialogBody>

        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={saving}>
            {t('common.cancel')}
          </Button>
          <Button onClick={handleSave} disabled={saving || loading}>
            {saving ? t('common.saving') : t('common.save')}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
