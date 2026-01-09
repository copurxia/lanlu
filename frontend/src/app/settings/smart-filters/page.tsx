'use client';

import { useState, useEffect, useCallback, useRef } from 'react';
import { logger } from '@/lib/logger';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Switch } from '@/components/ui/switch';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Dialog, DialogBody, DialogContent, DialogFooter } from '@/components/ui/dialog';
import { Filter, Plus, Pencil, Trash2, GripVertical, ChevronUp, ChevronDown } from 'lucide-react';
import { useLanguage } from '@/contexts/LanguageContext';
import { useAuth } from '@/contexts/AuthContext';
import { getApiUrl } from '@/lib/api';
import { useToast } from '@/hooks/use-toast';
import { useConfirmContext } from '@/contexts/ConfirmProvider';
import { ICON_OPTIONS, SORT_BY_OPTIONS, getIconByValue } from '@/lib/constants';

interface SmartFilter {
  id: number;
  name: string;
  translations: Record<string, { text?: string; intro?: string }>;
  icon: string;
  query: string;
  sort_by: string;
  sort_order: string;
  date_from: string;
  date_to: string;
  newonly: boolean;
  untaggedonly: boolean;
  sort_order_num: number;
  enabled: boolean;
}

export default function SmartFiltersPage() {
  const { t, language } = useLanguage();
  const { token } = useAuth();
  const { success } = useToast();
  const { confirm } = useConfirmContext();
  const [filters, setFilters] = useState<SmartFilter[]>([]);
  const [loading, setLoading] = useState(true);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editingFilter, setEditingFilter] = useState<SmartFilter | null>(null);

  // Drag state
  const [dragIndex, setDragIndex] = useState<number | null>(null);
  const [dropIndex, setDropIndex] = useState<number | null>(null);
  const draggedItem = useRef<SmartFilter | null>(null);

  const [formData, setFormData] = useState<Partial<SmartFilter>>({
    name: '',
    translations: {},
    icon: 'Filter',
    query: '',
    sort_by: '',
    sort_order: 'desc',
    date_from: '',
    date_to: '',
    newonly: false,
    untaggedonly: false,
    enabled: true,
  });

  const loadFilters = useCallback(async () => {
    try {
      setLoading(true);
      const response = await fetch(getApiUrl('/api/admin/smart_filters'), {
        headers: {
          'Authorization': `Bearer ${token}`,
        },
      });
      if (response.ok) {
        const data = await response.json();
        setFilters(data.data?.items || []);
      }
    } catch (error) {
      logger.apiError('load smart filters', error);
    } finally {
      setLoading(false);
    }
  }, [token]);

  useEffect(() => {
    loadFilters();
  }, [loadFilters]);

  const handleCreate = () => {
    setEditingFilter(null);
    setFormData({
      name: '',
      translations: {},
      icon: 'Filter',
      query: '',
      sort_by: '_default',
      sort_order: 'desc',
      date_from: '',
      date_to: '',
      newonly: false,
      untaggedonly: false,
      enabled: true,
    });
    setDialogOpen(true);
  };

  const handleEdit = (filter: SmartFilter) => {
    setEditingFilter(filter);
    setFormData({
      name: filter.name,
      translations: filter.translations || {},
      icon: filter.icon || 'Filter',
      query: filter.query,
      sort_by: filter.sort_by || '_default',
      sort_order: filter.sort_order || 'desc',
      date_from: filter.date_from,
      date_to: filter.date_to,
      newonly: filter.newonly,
      untaggedonly: filter.untaggedonly,
      enabled: filter.enabled,
    });
    setDialogOpen(true);
  };

  const handleSave = async () => {
    try {
      const url = editingFilter
        ? getApiUrl(`/api/admin/smart_filters/${editingFilter.id}`)
        : getApiUrl('/api/admin/smart_filters');
      const method = editingFilter ? 'PUT' : 'POST';

      // Convert _default back to empty string for API
      const dataToSave = {
        ...formData,
        sort_by: formData.sort_by === '_default' ? '' : formData.sort_by,
      };

      const response = await fetch(url, {
        method,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify(dataToSave),
      });

      if (response.ok) {
        setDialogOpen(false);
        loadFilters();
      }
    } catch (error) {
      logger.operationFailed('save smart filter', error);
    }
  };

  const handleDelete = async (id: number) => {
    const confirmed = await confirm({
      title: '确认删除',
      description: t('common.confirm') + '?',
      confirmText: '删除',
      cancelText: '取消',
      variant: 'destructive',
    });

    if (!confirmed) return;

    try {
      const response = await fetch(getApiUrl(`/api/admin/smart_filters/${id}`), {
        method: 'DELETE',
        headers: {
          'Authorization': `Bearer ${token}`,
        },
      });

      if (response.ok) {
        loadFilters();
        success('删除成功');
      }
    } catch (error) {
      logger.operationFailed('delete smart filter', error);
    }
  };

  const handleToggle = async (id: number) => {
    try {
      const response = await fetch(getApiUrl(`/api/admin/smart_filters/${id}/toggle`), {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
        },
      });

      if (response.ok) {
        loadFilters();
      }
    } catch (error) {
      logger.operationFailed('toggle smart filter', error);
    }
  };

  // Drag and drop handlers
  const handleDragStart = (e: React.DragEvent, index: number) => {
    draggedItem.current = filters[index];
    setDragIndex(index);
    e.dataTransfer.effectAllowed = 'move';
    e.dataTransfer.setData('text/plain', index.toString());
  };

  const handleDragOver = (e: React.DragEvent, index: number) => {
    e.preventDefault();
    e.dataTransfer.dropEffect = 'move';
    if (dragIndex !== null && index !== dragIndex) {
      setDropIndex(index);
    }
  };

  const handleDragLeave = () => {
    setDropIndex(null);
  };

  const handleDrop = async (e: React.DragEvent, targetIndex: number) => {
    e.preventDefault();

    if (dragIndex === null || dragIndex === targetIndex) {
      setDragIndex(null);
      setDropIndex(null);
      return;
    }

    // Reorder the filters array
    const newFilters = [...filters];
    const [movedItem] = newFilters.splice(dragIndex, 1);
    newFilters.splice(targetIndex, 0, movedItem);

    // Update local state immediately for responsive UI
    setFilters(newFilters);
    setDragIndex(null);
    setDropIndex(null);

    // Save new order to backend
    await saveSortOrder(newFilters);
  };

  const handleDragEnd = () => {
    setDragIndex(null);
    setDropIndex(null);
    draggedItem.current = null;
  };

  const handleMoveUp = async (index: number) => {
    if (index === 0) return;
    const newFilters = [...filters];
    [newFilters[index - 1], newFilters[index]] = [newFilters[index], newFilters[index - 1]];
    setFilters(newFilters);
    await saveSortOrder(newFilters);
  };

  const handleMoveDown = async (index: number) => {
    if (index >= filters.length - 1) return;
    const newFilters = [...filters];
    [newFilters[index], newFilters[index + 1]] = [newFilters[index + 1], newFilters[index]];
    setFilters(newFilters);
    await saveSortOrder(newFilters);
  };

  const saveSortOrder = async (updatedFilters: SmartFilter[]) => {
    try {
      const orders = updatedFilters.map((filter, idx) => ({
        id: filter.id,
        sort_order_num: idx,
      }));

      const response = await fetch(getApiUrl('/api/admin/smart_filters/reorder'), {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({ orders }),
      });

      if (!response.ok) {
        logger.operationFailed('save sort order', new Error('Failed to save sort order'));
        loadFilters(); // Reload on error
      }
    } catch (error) {
      logger.operationFailed('save sort order', error);
      loadFilters(); // Reload on error
    }
  };

  const getIconComponent = (iconName: string) => {
    const IconComponent = getIconByValue(iconName);
    return <IconComponent className="h-4 w-4" />;
  };

  const getSortByLabel = (sortBy: string) => {
    if (!sortBy) return t('settings.smartFilterDefault');
    switch (sortBy) {
      case 'date_added': return t('home.dateAdded');
      case 'lastread': return t('home.lastRead');
      case 'title': return t('home.titleSort');
      case 'pagecount': return t('home.pageCount');
      default: return sortBy;
    }
  };

  const getSortOrderLabel = (sortOrder: string) => {
    switch (sortOrder) {
      case 'asc': return t('common.asc');
      case 'desc': return t('common.desc');
      default: return t('common.desc');
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div className="space-y-1">
          <h2 className="text-xl font-semibold flex items-center gap-2">
            <Filter className="w-5 h-5" />
            {t('settings.smartFilters')}
          </h2>
          <p className="text-sm text-muted-foreground">{t('settings.smartFiltersDescription')}</p>
        </div>
        <Button onClick={handleCreate}>
          <Plus className="w-4 h-4 mr-2" />
          {t('common.add')}
        </Button>
      </div>

      <div className="space-y-4">
        {loading ? (
          <div className="text-center py-8 text-muted-foreground">{t('common.loading')}</div>
        ) : filters.length === 0 ? (
          <div className="text-center py-8 text-muted-foreground">{t('common.noData')}</div>
        ) : (
          <div className="space-y-2">
            {filters.map((filter, index) => (
              <div
                key={filter.id}
                draggable
                onDragStart={(e) => handleDragStart(e, index)}
                onDragOver={(e) => handleDragOver(e, index)}
                onDragLeave={handleDragLeave}
                onDrop={(e) => handleDrop(e, index)}
                onDragEnd={handleDragEnd}
                className={`flex items-center gap-4 p-3 border rounded-lg transition-all
                  ${dragIndex === index ? 'opacity-50 scale-[0.98]' : ''}
                  ${dropIndex === index ? 'border-primary border-2 bg-primary/5' : 'hover:bg-muted/50'}
                  cursor-grab active:cursor-grabbing
                `}
              >
                <div className="flex items-center text-muted-foreground">
                  <GripVertical className="h-5 w-5" />
                </div>
                <div className="flex items-center gap-2 min-w-[120px]">
                  {getIconComponent(filter.icon)}
                  <span className="font-medium">
                    {language !== 'zh' && filter.translations?.[language]?.text ? filter.translations[language].text : filter.name}
                  </span>
                </div>
                <div className="flex-1 text-sm text-muted-foreground truncate">
                  {filter.query && <span className="mr-2">Q: {filter.query}</span>}
                  {filter.newonly && <span className="mr-2 text-blue-500">{t('search.newOnly')}</span>}
                  {filter.untaggedonly && <span className="mr-2 text-orange-500">{t('search.untaggedOnly')}</span>}
                  {filter.date_from && <span className="mr-2">{t('settings.smartFilterDateFrom')}: {filter.date_from}</span>}
                  <span>{t('search.sortBy')}: {getSortByLabel(filter.sort_by)} {getSortOrderLabel(filter.sort_order)}</span>
                </div>
                <div className="flex items-center gap-2">
                  {/* 第一项显示下移按钮 */}
                  {index === 0 && filters.length > 1 && (
                    <Button
                      variant="ghost"
                      size="icon"
                      onClick={() => handleMoveDown(index)}
                      className="h-8 w-8"
                    >
                      <ChevronDown className="h-4 w-4" />
                    </Button>
                  )}
                  {/* 其他项显示上移按钮 */}
                  {index > 0 && (
                    <Button
                      variant="ghost"
                      size="icon"
                      onClick={() => handleMoveUp(index)}
                      className="h-8 w-8"
                    >
                      <ChevronUp className="h-4 w-4" />
                    </Button>
                  )}
                  <Switch
                    checked={filter.enabled}
                    onCheckedChange={() => handleToggle(filter.id)}
                  />
                  <Button variant="ghost" size="icon" onClick={() => handleEdit(filter)}>
                    <Pencil className="h-4 w-4" />
                  </Button>
                  <Button variant="ghost" size="icon" onClick={() => handleDelete(filter.id)}>
                    <Trash2 className="h-4 w-4 text-destructive" />
                  </Button>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent>
          <DialogBody className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <label className="text-sm font-medium">{t('settings.smartFilterName')} (中文)</label>
                <Input
                  value={formData.name || ''}
                  onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                  placeholder={t('settings.smartFilterNamePlaceholder')}
                />
              </div>
              <div className="space-y-2">
                <label className="text-sm font-medium">{t('settings.smartFilterName')} (English)</label>
                <Input
                  value={formData.translations?.en?.text || ''}
                  onChange={(e) => setFormData({
                    ...formData,
                    translations: {
                      ...formData.translations,
                      en: { ...formData.translations?.en, text: e.target.value }
                    }
                  })}
                  placeholder="English name"
                />
              </div>
            </div>

            <div className="space-y-2">
              <label className="text-sm font-medium">{t('settings.smartFilterIcon')}</label>
              <Select
                value={formData.icon || 'Filter'}
                onValueChange={(value) => setFormData({ ...formData, icon: value })}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {ICON_OPTIONS.map((opt) => (
                    <SelectItem key={opt.value} value={opt.value}>
                      <div className="flex items-center gap-2">
                        <opt.icon className="h-4 w-4" />
                        <span>{opt.label}</span>
                      </div>
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-2">
              <label className="text-sm font-medium">{t('search.keyword')}</label>
              <Input
                value={formData.query || ''}
                onChange={(e) => setFormData({ ...formData, query: e.target.value })}
                placeholder={t('search.keywordPlaceholder')}
              />
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <label className="text-sm font-medium">{t('search.sortBy')}</label>
                <Select
                  value={formData.sort_by || '_default'}
                  onValueChange={(value) => setFormData({ ...formData, sort_by: value })}
                >
                  <SelectTrigger>
                    <SelectValue placeholder={t('settings.smartFilterDefault')} />
                  </SelectTrigger>
                  <SelectContent>
                    {SORT_BY_OPTIONS.map((opt) => (
                      <SelectItem key={opt.value} value={opt.value}>
                        {opt.value === '_default' ? t('settings.smartFilterDefault') : t(`home.${opt.label}`)}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-2">
                <label className="text-sm font-medium">{t('common.sort')}</label>
                <Select
                  value={formData.sort_order || 'desc'}
                  onValueChange={(value) => setFormData({ ...formData, sort_order: value })}
                >
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="asc">{t('common.asc')}</SelectItem>
                    <SelectItem value="desc">{t('common.desc')}</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <label className="text-sm font-medium">{t('settings.smartFilterDateFrom')}</label>
                <Input
                  value={formData.date_from || ''}
                  onChange={(e) => setFormData({ ...formData, date_from: e.target.value })}
                  placeholder="-7 (7 days ago)"
                />
                <p className="text-xs text-muted-foreground">{t('settings.smartFilterDateFromHint')}</p>
              </div>
              <div className="space-y-2">
                <label className="text-sm font-medium">{t('settings.smartFilterDateTo')}</label>
                <Input
                  value={formData.date_to || ''}
                  onChange={(e) => setFormData({ ...formData, date_to: e.target.value })}
                  placeholder="0 (today)"
                />
              </div>
            </div>

            <div className="space-y-3 border-t pt-4">
              <div className="flex items-center justify-between">
                <label className="text-sm font-medium">{t('search.newOnly')}</label>
                <Switch
                  checked={formData.newonly || false}
                  onCheckedChange={(checked) => setFormData({ ...formData, newonly: checked })}
                />
              </div>
              <div className="flex items-center justify-between">
                <label className="text-sm font-medium">{t('search.untaggedOnly')}</label>
                <Switch
                  checked={formData.untaggedonly || false}
                  onCheckedChange={(checked) => setFormData({ ...formData, untaggedonly: checked })}
                />
              </div>
            </div>
          </DialogBody>

          <DialogFooter>
            <Button variant="outline" onClick={() => setDialogOpen(false)}>
              {t('common.cancel')}
            </Button>
            <Button onClick={handleSave} disabled={!formData.name}>
              {t('common.save')}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
