'use client';

import { useEffect, useMemo, useState } from 'react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { Dialog, DialogBody, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Folder, Plus, Search, Edit2, Trash2, Play, FolderOpen, RotateCcw } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { useLanguage } from '@/contexts/LanguageContext';
import { CategoryService, type Category, type CategoryCreateRequest, type CategoryUpdateRequest } from '@/lib/services/category-service';
import { PluginService, type Plugin } from '@/lib/services/plugin-service';
import { useToast } from '@/hooks/use-toast';
import { useConfirmContext } from '@/contexts/ConfirmProvider';
import { Checkbox } from '@/components/ui/checkbox';

export default function CategoriesSettingsPage() {
  const { t } = useLanguage();
  const { user, isAuthenticated } = useAuth();
  const { success, error: showError } = useToast();
  const { confirm } = useConfirmContext();

  const [loading, setLoading] = useState(false);

  // Categories list
  const [categories, setCategories] = useState<Category[]>([]);
  const [categoriesLoading, setCategoriesLoading] = useState(false);

  // Filters
  const [searchQuery, setSearchQuery] = useState('');
  const [enabledFilter, setEnabledFilter] = useState<string>('all');

  // Create form
  const [createForm, setCreateForm] = useState<CategoryCreateRequest>({
    name: '',
    scan_path: '',
    description: '',
    icon: '',
    sort_order: 0,
    enabled: true,
    plugins: [],
  });

  // Create dialog
  const [createDialogOpen, setCreateDialogOpen] = useState(false);

  // Edit dialog
  const [editDialogOpen, setEditDialogOpen] = useState(false);
  const [editingCategory, setEditingCategory] = useState<Category | null>(null);
  const [editForm, setEditForm] = useState<CategoryUpdateRequest>({});

  // Metadata plugins
  const [metadataPlugins, setMetadataPlugins] = useState<Plugin[]>([]);

  // Check if current user is admin
  const isAdmin = useMemo(() => {
    return isAuthenticated && user?.isAdmin === true;
  }, [isAuthenticated, user?.isAdmin]);

  // Load categories
  const loadCategories = async () => {
    if (!isAuthenticated) return;
    setCategoriesLoading(true);
    try {
      const cats = await CategoryService.getAllCategories();
      // Apply filters
      let filtered = cats;
      if (searchQuery) {
        const query = searchQuery.toLowerCase();
        filtered = filtered.filter(cat =>
          cat.name.toLowerCase().includes(query) ||
          cat.description.toLowerCase().includes(query) ||
          cat.scan_path.toLowerCase().includes(query)
        );
      }
      if (enabledFilter !== 'all') {
        filtered = filtered.filter(cat => cat.enabled === (enabledFilter === 'enabled'));
      }
      setCategories(filtered);
    } catch (e: any) {
      showError(e?.response?.data?.message || e?.message || t('settings.categoryLoadFailed'));
    } finally {
      setCategoriesLoading(false);
    }
  };

  useEffect(() => {
    if (isAuthenticated) {
      void loadCategories();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isAuthenticated, searchQuery, enabledFilter]);

  // Load metadata plugins
  useEffect(() => {
    const loadMetadataPlugins = async () => {
      try {
        const plugins = await PluginService.getMetadataPlugins();
        setMetadataPlugins(plugins);
      } catch (e) {
        console.error('Failed to load metadata plugins:', e);
      }
    };
    if (isAuthenticated) {
      void loadMetadataPlugins();
    }
  }, [isAuthenticated]);

  const handleCreateCategory = async () => {
    if (!createForm.name.trim() || !createForm.scan_path.trim()) {
      showError(t('settings.categoryNamePathRequired'));
      return;
    }

    setLoading(true);

    try {
      await CategoryService.createCategory(createForm);
      setCreateForm({
        name: '',
        scan_path: '',
        description: '',
        icon: '',
        sort_order: 0,
        enabled: true,
      });
      setCreateDialogOpen(false);
      await loadCategories();
      success(t('settings.categoryCreatedSuccess'));
    } catch (e: any) {
      showError(e?.response?.data?.message || e?.message || t('settings.categoryCreateFailed'));
    } finally {
      setLoading(false);
    }
  };

  const handleEditCategory = (category: Category) => {
    setEditingCategory(category);
    setEditForm({
      name: category.name,
      scan_path: category.scan_path,
      description: category.description,
      icon: category.icon,
      sort_order: category.sort_order,
      enabled: category.enabled,
      plugins: category.plugins || [],
    });
    setEditDialogOpen(true);
  };

  const handleUpdateCategory = async () => {
    if (!editingCategory) return;
    if (!editForm.name?.trim() || !editForm.scan_path?.trim()) {
      showError(t('settings.categoryNamePathRequired'));
      return;
    }

    setLoading(true);

    try {
      await CategoryService.updateCategory(editingCategory.catid, editForm);
      setEditDialogOpen(false);
      setEditingCategory(null);
      await loadCategories();
      success(t('settings.categoryUpdatedSuccess'));
    } catch (e: any) {
      showError(e?.response?.data?.message || e?.message || t('settings.categoryUpdateFailed'));
    } finally {
      setLoading(false);
    }
  };

  const handleDeleteCategory = async (catid: string) => {
    const confirmed = await confirm({
      title: t('settings.categoryDeleteConfirmTitle'),
      description: t('settings.categoryDeleteConfirm'),
      confirmText: t('common.delete'),
      cancelText: t('common.cancel'),
      variant: 'destructive',
    });

    if (!confirmed) return;

    setLoading(true);
    try {
      const result = await CategoryService.deleteCategory(catid);
      if (result.success) {
        await loadCategories();
        success(t('settings.categoryDeletedSuccess'));
      } else {
        showError(result.error || t('settings.categoryDeleteFailed'));
      }
    } catch (e: any) {
      showError(e?.response?.data?.message || e?.message || t('settings.categoryDeleteFailed'));
    } finally {
      setLoading(false);
    }
  };

  const handleToggleEnabled = async (catid: string, enabled: boolean) => {
    try {
      await CategoryService.updateCategory(catid, { enabled });
      await loadCategories();
    } catch (e: any) {
      showError(e?.response?.data?.message || e?.message || t('settings.categoryUpdateFailed'));
    }
  };

  const handleScanCategory = async (catid: string) => {
    setLoading(true);
    try {
      const result = await CategoryService.scanCategory(catid);
      if (result.success) {
        success(t('settings.categoryScanStarted'));
      } else {
        showError(result.error || t('settings.categoryScanFailed'));
      }
    } catch (e: any) {
      showError(e?.response?.data?.message || e?.message || t('settings.categoryScanFailed'));
    } finally {
      setLoading(false);
    }
  };

  if (!isAuthenticated) {
    return (
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div className="space-y-1">
            <h2 className="text-xl font-semibold flex items-center gap-2">
              <FolderOpen className="w-5 h-5" />
              {t('settings.categories')}
            </h2>
            <p className="text-sm text-muted-foreground">{t('auth.loginToManageTokens')}</p>
          </div>
        </div>
        <Card>
          <CardContent className="pt-6 space-y-4">
            {/* Empty content */}
          </CardContent>
        </Card>
      </div>
    );
  }

  if (!isAdmin) {
    return (
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div className="space-y-1">
            <h2 className="text-xl font-semibold flex items-center gap-2">
              <FolderOpen className="w-5 h-5" />
              {t('settings.categories')}
            </h2>
            <p className="text-sm text-muted-foreground">{t('common.accessDenied')}</p>
          </div>
        </div>
        <Card>
          <CardContent className="pt-6 space-y-4">
            {/* Empty content */}
          </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div className="space-y-1">
          <h2 className="text-xl font-semibold flex items-center gap-2">
            <FolderOpen className="w-5 h-5" />
            {t('settings.categories')}
          </h2>
          <p className="text-sm text-muted-foreground">{t('settings.categoriesDescription')}</p>
        </div>
      </div>

      <div className="flex flex-col gap-2 sm:flex-row sm:items-center">
        <div className="relative flex-1 min-w-0">
          <Search className="absolute left-2 top-2.5 h-4 w-4 text-muted-foreground" />
          <Input
            placeholder={t('settings.categorySearchPlaceholder')}
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="pl-8"
          />
        </div>

        {/* Keep the search field readable on mobile by collapsing actions into icons. */}
        <div className="flex gap-2">
          <Select value={enabledFilter} onValueChange={setEnabledFilter}>
            <SelectTrigger className="flex-1 min-w-0 sm:flex-none sm:w-[180px]">
              <SelectValue placeholder={t('settings.categoryAllStatuses')} />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">{t('settings.categoryAllStatuses')}</SelectItem>
              <SelectItem value="enabled">{t('settings.categoryEnabled')}</SelectItem>
              <SelectItem value="disabled">{t('settings.categoryDisabled')}</SelectItem>
            </SelectContent>
          </Select>

          {/* Mobile: icon-only clear */}
          <Button
            type="button"
            variant="outline"
            size="icon"
            className="sm:hidden"
            aria-label={t('common.reset')}
            title={t('common.reset')}
            onClick={() => {
              setSearchQuery('');
              setEnabledFilter('all');
            }}
          >
            <RotateCcw className="h-4 w-4" />
          </Button>
          {/* Desktop: normal reset */}
          <Button
            type="button"
            variant="outline"
            className="hidden sm:inline-flex items-center gap-2"
            onClick={() => {
              setSearchQuery('');
              setEnabledFilter('all');
            }}
          >
            <RotateCcw className="h-4 w-4" />
            {t('common.reset')}
          </Button>

          {/* Mobile: icon-only create */}
          <Button
            type="button"
            size="icon"
            className="sm:hidden"
            aria-label={t('settings.categoryCreate')}
            title={t('settings.categoryCreate')}
            onClick={() => setCreateDialogOpen(true)}
          >
            <Plus className="h-4 w-4" />
          </Button>
          {/* Desktop: normal create */}
          <Button
            type="button"
            className="hidden sm:inline-flex items-center gap-2"
            onClick={() => setCreateDialogOpen(true)}
          >
            <Plus className="h-4 w-4" />
            {t('settings.categoryCreate')}
          </Button>
        </div>
      </div>

      {categoriesLoading ? (
        <p className="text-sm text-muted-foreground">{t('common.loading')}</p>
      ) : categories.length === 0 ? (
        <p className="text-sm text-muted-foreground">{t('settings.categoryNoCategories')}</p>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {categories.map((category) => (
            <Card key={category.catid} className="hover:shadow-md transition-shadow">
              <CardHeader className="pb-3">
                <div className="flex items-start justify-between">
                  <div className="flex items-center gap-2">
                    {category.icon && <span className="text-2xl">{category.icon}</span>}
                    <CardTitle className="text-lg">{category.name}</CardTitle>
                  </div>
                  <Switch
                    checked={category.enabled}
                    onCheckedChange={(checked) => handleToggleEnabled(category.catid, checked)}
                    disabled={loading}
                  />
                </div>
                <CardDescription className="line-clamp-2">
                  {category.description || t('settings.categoryNoDescription')}
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-3">
                <div className="space-y-2 text-sm">
                  <div className="flex items-center gap-2 text-muted-foreground">
                    <Folder className="w-4 h-4" />
                    <span className="truncate">{category.scan_path}</span>
                  </div>
                  <div className="flex items-center gap-2 text-muted-foreground">
                    <Badge variant="outline" className="text-xs">
                      {category.archive_count} {t('settings.categoryArchives')}
                    </Badge>
                    <span className="text-xs">
                      {t('settings.categorySortOrder')}: {category.sort_order}
                    </span>
                  </div>
                </div>
                <div className="flex gap-2 pt-2">
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => handleScanCategory(category.catid)}
                    disabled={loading || !category.enabled}
                    title={t('settings.categoryScanTooltip')}
                    className="flex-1"
                  >
                    <Play className="w-4 h-4 mr-1" />
                    {t('settings.categoryScan')}
                  </Button>
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => handleEditCategory(category)}
                    disabled={loading}
                  >
                    <Edit2 className="w-4 h-4" />
                  </Button>
                  <Button
                    variant="destructive"
                    size="sm"
                    onClick={() => handleDeleteCategory(category.catid)}
                    disabled={loading}
                  >
                    <Trash2 className="w-4 h-4" />
                  </Button>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {/* Create Dialog */}
      <Dialog open={createDialogOpen} onOpenChange={(open) => {
        setCreateDialogOpen(open);
        if (!open) {
          setCreateForm({
            name: '',
            scan_path: '',
            description: '',
            icon: '',
            sort_order: 0,
            enabled: true,
            plugins: [],
          });
        }
      }}>
        <DialogContent size="lg">
          <DialogHeader>
            <DialogTitle>{t('settings.createNewCategory')}</DialogTitle>
          </DialogHeader>
          <DialogBody className="space-y-4">
            <div className="grid gap-3 sm:grid-cols-2">
              <div className="space-y-2">
                <Label htmlFor="create-name">{t('settings.categoryName')} *</Label>
                <Input
                  id="create-name"
                  value={createForm.name}
                  onChange={(e) => setCreateForm({ ...createForm, name: e.target.value })}
                  placeholder={t('settings.categoryNamePlaceholder')}
                  disabled={loading}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="create-scan-path">{t('settings.categoryScanPath')} *</Label>
                <Input
                  id="create-scan-path"
                  value={createForm.scan_path}
                  onChange={(e) => setCreateForm({ ...createForm, scan_path: e.target.value })}
                  placeholder={t('settings.categoryScanPathPlaceholder')}
                  disabled={loading}
                />
              </div>
            </div>
            <div className="space-y-2">
              <Label htmlFor="create-description">{t('settings.categoryDescription')}</Label>
              <Textarea
                id="create-description"
                value={createForm.description}
                onChange={(e) => setCreateForm({ ...createForm, description: e.target.value })}
                placeholder={t('settings.categoryDescriptionPlaceholder')}
                disabled={loading}
                rows={2}
              />
            </div>
            <div className="flex items-center gap-4">
              <div className="space-y-2">
                <Label htmlFor="create-icon">{t('settings.categoryIcon')}</Label>
                <Input
                  id="create-icon"
                  value={createForm.icon}
                  onChange={(e) => setCreateForm({ ...createForm, icon: e.target.value })}
                  placeholder={t('settings.categoryIconPlaceholder')}
                  disabled={loading}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="create-sort-order">{t('settings.categorySortOrder')}</Label>
                <Input
                  id="create-sort-order"
                  type="number"
                  value={createForm.sort_order}
                  onChange={(e) => setCreateForm({ ...createForm, sort_order: parseInt(e.target.value) || 0 })}
                  placeholder="0"
                  disabled={loading}
                />
              </div>
              <div className="flex items-center space-x-2">
                <Switch
                  id="create-enabled"
                  checked={createForm.enabled}
                  onCheckedChange={(checked) => setCreateForm({ ...createForm, enabled: checked })}
                  disabled={loading}
                />
                <Label htmlFor="create-enabled">{t('settings.categoryEnabled')}</Label>
              </div>
            </div>
            {metadataPlugins.length > 0 && (
              <div className="space-y-2">
                <Label>{t('settings.categoryPlugins')}</Label>
                <p className="text-xs text-muted-foreground mb-2">
                  {t('settings.categoryPluginsDescription')}
                </p>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                  {metadataPlugins.map((plugin) => (
                    <div key={plugin.namespace} className="flex items-center space-x-2">
                      <Checkbox
                        id={`create-plugin-${plugin.namespace}`}
                        checked={createForm.plugins?.includes(plugin.namespace) || false}
                        onCheckedChange={(checked) => {
                          const current = createForm.plugins || [];
                          if (checked) {
                            setCreateForm({ ...createForm, plugins: [...current, plugin.namespace] });
                          } else {
                            setCreateForm({ ...createForm, plugins: current.filter(p => p !== plugin.namespace) });
                          }
                        }}
                        disabled={loading}
                      />
                      <Label htmlFor={`create-plugin-${plugin.namespace}`} className="text-sm cursor-pointer">
                        {plugin.name}
                      </Label>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </DialogBody>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setCreateDialogOpen(false)}
              disabled={loading}
            >
              {t('common.cancel')}
            </Button>
            <Button
              onClick={handleCreateCategory}
              disabled={loading || !createForm.name.trim() || !createForm.scan_path.trim()}
            >
              {loading ? t('settings.categoryCreating') : t('settings.categoryCreate')}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Edit Dialog */}
      <Dialog open={editDialogOpen} onOpenChange={(open) => {
        setEditDialogOpen(open);
        if (!open) {
          setEditingCategory(null);
          setEditForm({});
        }
      }}>
        <DialogContent size="lg">
          <DialogBody className="space-y-4">
            <div className="grid gap-3 sm:grid-cols-2">
              <div className="space-y-2">
                <Label htmlFor="edit-name">{t('settings.categoryName')} *</Label>
                <Input
                  id="edit-name"
                  value={editForm.name || ''}
                  onChange={(e) => setEditForm({ ...editForm, name: e.target.value })}
                  placeholder={t('settings.categoryNamePlaceholder')}
                  disabled={loading}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="edit-scan-path">{t('settings.categoryScanPath')} *</Label>
                <Input
                  id="edit-scan-path"
                  value={editForm.scan_path || ''}
                  onChange={(e) => setEditForm({ ...editForm, scan_path: e.target.value })}
                  placeholder={t('settings.categoryScanPathPlaceholder')}
                  disabled={loading}
                />
              </div>
            </div>
            <div className="space-y-2">
              <Label htmlFor="edit-description">{t('settings.categoryDescription')}</Label>
              <Textarea
                id="edit-description"
                value={editForm.description || ''}
                onChange={(e) => setEditForm({ ...editForm, description: e.target.value })}
                placeholder={t('settings.categoryDescriptionPlaceholder')}
                disabled={loading}
                rows={2}
              />
            </div>
            <div className="grid gap-3 sm:grid-cols-2">
              <div className="space-y-2">
                <Label htmlFor="edit-icon">{t('settings.categoryIcon')}</Label>
                <Input
                  id="edit-icon"
                  value={editForm.icon || ''}
                  onChange={(e) => setEditForm({ ...editForm, icon: e.target.value })}
                  placeholder={t('settings.categoryIconPlaceholder')}
                  disabled={loading}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="edit-sort-order">{t('settings.categorySortOrder')}</Label>
                <Input
                  id="edit-sort-order"
                  type="number"
                  value={editForm.sort_order || 0}
                  onChange={(e) => setEditForm({ ...editForm, sort_order: parseInt(e.target.value) || 0 })}
                  placeholder="0"
                  disabled={loading}
                />
              </div>
            </div>
            {metadataPlugins.length > 0 && (
              <div className="space-y-2">
                <Label>{t('settings.categoryPlugins')}</Label>
                <p className="text-xs text-muted-foreground mb-2">
                  {t('settings.categoryPluginsDescription')}
                </p>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                  {metadataPlugins.map((plugin) => (
                    <div key={plugin.namespace} className="flex items-center space-x-2">
                      <Checkbox
                        id={`edit-plugin-${plugin.namespace}`}
                        checked={editForm.plugins?.includes(plugin.namespace) || false}
                        onCheckedChange={(checked) => {
                          const current = editForm.plugins || [];
                          if (checked) {
                            setEditForm({ ...editForm, plugins: [...current, plugin.namespace] });
                          } else {
                            setEditForm({ ...editForm, plugins: current.filter(p => p !== plugin.namespace) });
                          }
                        }}
                        disabled={loading}
                      />
                      <Label htmlFor={`edit-plugin-${plugin.namespace}`} className="text-sm cursor-pointer">
                        {plugin.name}
                      </Label>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </DialogBody>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setEditDialogOpen(false)}
              disabled={loading}
            >
              {t('common.cancel')}
            </Button>
            <Button
              onClick={handleUpdateCategory}
              disabled={loading || !editForm.name?.trim() || !editForm.scan_path?.trim()}
            >
              {loading ? t('settings.categorySaving') : t('settings.categorySaveChanges')}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
