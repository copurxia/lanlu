'use client';

import { useEffect, useMemo, useState } from 'react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { Textarea } from '@/components/ui/textarea';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Tag, Plus, Search, Download, Upload, Edit2, Trash2, Save, X } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { useLanguage } from '@/contexts/LanguageContext';
import { TagService } from '@/lib/tag-service';

interface TagItem {
  id: number;
  namespace: string;
  name: string;
  translations: Record<string, { text: string; intro: string }>;
  links: string;
  createdAt?: string;
  updatedAt?: string;
}

interface CreateTagForm {
  namespace: string;
  name: string;
  zhText: string;
  zhIntro: string;
  enText: string;
  enIntro: string;
  links: string;
}

interface EditTagForm {
  id: number;
  namespace: string;
  name: string;
  zhText: string;
  zhIntro: string;
  enText: string;
  enIntro: string;
  links: string;
}

export default function TagsSettingsPage() {
  const { t } = useLanguage();
  const { user, isAuthenticated } = useAuth();

  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [successMsg, setSuccessMsg] = useState<string | null>(null);

  // Tags list
  const [tags, setTags] = useState<TagItem[]>([]);
  const [tagsLoading, setTagsLoading] = useState(false);
  const [totalTags, setTotalTags] = useState(0);
  const [currentPage, setCurrentPage] = useState(1);
  const [pageSize] = useState(20);

  // Filters
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedNamespace, setSelectedNamespace] = useState<string>('all');

  // Namespaces
  const [namespaces, setNamespaces] = useState<string[]>([]);

  // Create form
  const [createForm, setCreateForm] = useState<CreateTagForm>({
    namespace: '',
    name: '',
    zhText: '',
    zhIntro: '',
    enText: '',
    enIntro: '',
    links: '',
  });

  // Edit dialog
  const [editDialogOpen, setEditDialogOpen] = useState(false);
  const [editingTag, setEditingTag] = useState<TagItem | null>(null);
  const [editForm, setEditForm] = useState<EditTagForm>({
    id: 0,
    namespace: '',
    name: '',
    zhText: '',
    zhIntro: '',
    enText: '',
    enIntro: '',
    links: '',
  });

  // Check if current user is admin
  const isAdmin = useMemo(() => {
    return isAuthenticated && user?.isAdmin === true;
  }, [isAuthenticated, user?.isAdmin]);

  // Load tags
  const loadTags = async () => {
    if (!isAuthenticated) return;
    setTagsLoading(true);
    try {
      const params: any = {
        page: currentPage,
        pageSize,
      };
      if (searchQuery) params.query = searchQuery;
      if (selectedNamespace && selectedNamespace !== 'all') params.namespace = selectedNamespace;

      const response = await TagService.list(params);
      setTags(response.items || []);
      setTotalTags(response.total || 0);
    } catch (e: any) {
      setError(e?.response?.data?.message || e?.message || t('settings.tagLoadFailed'));
    } finally {
      setTagsLoading(false);
    }
  };

  // Load namespaces
  const loadNamespaces = async () => {
    try {
      // Use TagService directly to get namespaces
      // Since there's no direct method, we'll fetch all tags and extract unique namespaces
      const response = await TagService.list({ limit: 1000 });
      const uniqueNamespaces = Array.from(
        new Set((response.items || []).map(tag => tag.namespace).filter(ns => ns))
      ).sort();
      setNamespaces(uniqueNamespaces);
    } catch (e) {
      // Silent fail for namespaces
    }
  };

  useEffect(() => {
    if (isAuthenticated) {
      void loadTags();
      void loadNamespaces();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isAuthenticated, currentPage, searchQuery, selectedNamespace]);

  const handleCreateTag = async () => {
    if (!createForm.namespace.trim() || !createForm.name.trim()) {
      setError(t('settings.tagNamespaceNameRequired'));
      return;
    }

    setLoading(true);
    setError(null);
    setSuccessMsg(null);

    try {
      const translations: Record<string, { text: string; intro: string }> = {};
      if (createForm.zhText || createForm.zhIntro) {
        translations.zh = {
          text: createForm.zhText,
          intro: createForm.zhIntro,
        };
      }
      if (createForm.enText || createForm.enIntro) {
        translations.en = {
          text: createForm.enText,
          intro: createForm.enIntro,
        };
      }

      await TagService.adminCreate({
        namespace: createForm.namespace.trim(),
        name: createForm.name.trim(),
        translations,
        links: createForm.links,
      });

      setSuccessMsg(t('settings.tagCreatedSuccess'));
      setCreateForm({
        namespace: '',
        name: '',
        zhText: '',
        zhIntro: '',
        enText: '',
        enIntro: '',
        links: '',
      });
      await loadTags();
      await loadNamespaces();
    } catch (e: any) {
      setError(e?.response?.data?.message || e?.message || t('settings.tagCreateFailed'));
      setSuccessMsg(null);
    } finally {
      setLoading(false);
    }
  };

  const handleEditTag = (tag: TagItem) => {
    setEditingTag(tag);
    setEditForm({
      id: tag.id,
      namespace: tag.namespace,
      name: tag.name,
      zhText: tag.translations.zh?.text || '',
      zhIntro: tag.translations.zh?.intro || '',
      enText: tag.translations.en?.text || '',
      enIntro: tag.translations.en?.intro || '',
      links: tag.links || '',
    });
    setEditDialogOpen(true);
  };

  const handleUpdateTag = async () => {
    if (!editForm.namespace.trim() || !editForm.name.trim()) {
      setError(t('settings.tagNamespaceNameRequired'));
      return;
    }

    setLoading(true);
    setError(null);
    setSuccessMsg(null);

    try {
      const translations: Record<string, { text: string; intro: string }> = {};
      if (editForm.zhText || editForm.zhIntro) {
        translations.zh = {
          text: editForm.zhText,
          intro: editForm.zhIntro,
        };
      }
      if (editForm.enText || editForm.enIntro) {
        translations.en = {
          text: editForm.enText,
          intro: editForm.enIntro,
        };
      }

      await TagService.adminUpdate(editForm.id, {
        translations,
        links: editForm.links,
      });

      setSuccessMsg(t('settings.tagUpdatedSuccess'));
      setEditDialogOpen(false);
      setEditingTag(null);
      await loadTags();
      await loadNamespaces();
    } catch (e: any) {
      setError(e?.response?.data?.message || e?.message || t('settings.tagUpdateFailed'));
      setSuccessMsg(null);
    } finally {
      setLoading(false);
    }
  };

  const handleDeleteTag = async (tagId: number) => {
    if (!confirm(t('settings.tagDeleteConfirm'))) {
      return;
    }

    setLoading(true);
    setError(null);
    try {
      await TagService.adminDelete(tagId);
      setSuccessMsg(t('settings.tagDeletedSuccess'));
      await loadTags();
    } catch (e: any) {
      setError(e?.response?.data?.message || e?.message || t('settings.tagDeleteFailed'));
    } finally {
      setLoading(false);
    }
  };

  const handleExport = async () => {
    try {
      const data = await TagService.adminExport();
      const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `tags-export-${new Date().toISOString().split('T')[0]}.json`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
      setSuccessMsg(t('settings.tagExportSuccess'));
    } catch (e: any) {
      setError(e?.response?.data?.message || e?.message || t('settings.tagExportFailed'));
    }
  };

  const handleImport = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file) return;

    if (!confirm(t('settings.tagImportConfirm'))) {
      return;
    }

    setLoading(true);
    setError(null);
    try {
      // Init import job
      const initResp = await TagService.adminImportInit();
      const job = initResp.job;

      // Upload file
      await TagService.adminImportUpload(job, file, initResp.chunk_size);

      setSuccessMsg(t('settings.tagImportStarted', { job }));
      await loadTags();
      await loadNamespaces();
    } catch (e: any) {
      setError(e?.response?.data?.message || e?.message || t('settings.tagImportFailed'));
    } finally {
      setLoading(false);
      // Reset file input
      event.target.value = '';
    }
  };

  if (!isAuthenticated) {
    return (
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div className="space-y-1">
            <h2 className="text-xl font-semibold flex items-center gap-2">
              <Tag className="w-5 h-5" />
              {t('settings.tags')}
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
              <Tag className="w-5 h-5" />
              {t('settings.tags')}
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
            <Tag className="w-5 h-5" />
            {t('settings.tags')}
          </h2>
          <p className="text-sm text-muted-foreground">{t('settings.tagsDescription')}</p>
        </div>
        <div className="flex gap-2">
          <Button
            variant="outline"
            onClick={handleExport}
            disabled={loading}
            className="flex items-center gap-2"
          >
            <Download className="w-4 h-4" />
            {t('common.export')}
          </Button>
          <label>
            <input
              type="file"
              accept=".json"
              onChange={handleImport}
              className="hidden"
              disabled={loading}
            />
            <Button
              variant="outline"
              disabled={loading}
              className="flex items-center gap-2 cursor-pointer"
              asChild
            >
              <span>
                <Upload className="w-4 h-4" />
                {t('common.import')}
              </span>
            </Button>
          </label>
          <TagDialog
            open={false}
            onOpenChange={() => {}}
            mode="create"
            form={createForm}
            setForm={setCreateForm as any}
            loading={loading}
            onCreate={handleCreateTag}
            t={t}
          />
        </div>
      </div>

      {error ? <p className="text-sm text-destructive">{error}</p> : null}
      {successMsg ? <p className="text-sm text-green-600">{successMsg}</p> : null}

      <Card>
        <CardHeader>
          <CardTitle>{t('settings.tagsList')}</CardTitle>
          <CardDescription>{t('settings.tagsListDescription')}</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex gap-2">
            <div className="relative flex-1">
              <Search className="absolute left-2 top-2.5 h-4 w-4 text-muted-foreground" />
              <Input
                placeholder={t('settings.tagSearchPlaceholder')}
                value={searchQuery}
                onChange={(e) => {
                  setSearchQuery(e.target.value);
                  setCurrentPage(1);
                }}
                className="pl-8"
              />
            </div>
            <Select value={selectedNamespace} onValueChange={(value) => {
              setSelectedNamespace(value);
              setCurrentPage(1);
            }}>
              <SelectTrigger className="w-[180px]">
                <SelectValue placeholder={t('settings.tagAllNamespaces')} />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">{t('settings.tagAllNamespaces')}</SelectItem>
                {namespaces.map((ns) => (
                  <SelectItem key={ns} value={ns}>
                    {ns}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Button
              variant="outline"
              onClick={() => {
                setSearchQuery('');
                setSelectedNamespace('all');
                setCurrentPage(1);
              }}
            >
              {t('common.clear')}
            </Button>
          </div>

          {tagsLoading ? (
            <p className="text-sm text-muted-foreground">{t('common.loading')}</p>
          ) : tags.length === 0 ? (
            <p className="text-sm text-muted-foreground">{t('settings.tagNoTags')}</p>
          ) : (
            <div className="space-y-2">
              {tags.map((tag) => (
                <div
                  key={tag.id}
                  className="flex flex-col gap-2 rounded-md border p-3 sm:flex-row sm:items-start sm:justify-between"
                >
                  <div className="min-w-0 space-y-1 flex-1">
                    <div className="flex items-center gap-2 flex-wrap">
                      {tag.namespace && (
                        <Badge variant="secondary">{tag.namespace}</Badge>
                      )}
                      <span className="font-medium">{tag.name}</span>
                    </div>
                    <div className="text-xs text-muted-foreground space-y-1">
                      {tag.translations.zh?.text && (
                        <div>中文: {tag.translations.zh.text}</div>
                      )}
                      {tag.translations.en?.text && (
                        <div>English: {tag.translations.en.text}</div>
                      )}
                      {tag.links && (
                        <div>Links: {tag.links}</div>
                      )}
                    </div>
                  </div>
                  <div className="flex gap-2">
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => handleEditTag(tag)}
                      disabled={loading}
                    >
                      <Edit2 className="w-4 h-4" />
                    </Button>
                    <Button
                      variant="destructive"
                      size="sm"
                      onClick={() => handleDeleteTag(tag.id)}
                      disabled={loading}
                    >
                      <Trash2 className="w-4 h-4" />
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          )}

          {totalTags > pageSize && (
            <div className="flex items-center justify-between">
              <p className="text-sm text-muted-foreground">
                {t('settings.tagShowingRange', { from: ((currentPage - 1) * pageSize) + 1, to: Math.min(currentPage * pageSize, totalTags), total: totalTags })}
              </p>
              <div className="flex gap-2">
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => setCurrentPage(prev => Math.max(1, prev - 1))}
                  disabled={currentPage === 1 || loading}
                >
                  {t('common.previous')}
                </Button>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => setCurrentPage(prev => prev + 1)}
                  disabled={currentPage * pageSize >= totalTags || loading}
                >
                  {t('common.next')}
                </Button>
              </div>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Tag Dialog - Create/Edit */}
      <TagDialog
        open={editDialogOpen}
        onOpenChange={(open) => {
          setEditDialogOpen(open);
          if (!open) {
            setEditingTag(null);
            setEditForm({
              id: 0,
              namespace: '',
              name: '',
              zhText: '',
              zhIntro: '',
              enText: '',
              enIntro: '',
              links: '',
            });
          }
        }}
        mode="edit"
        form={editForm}
        setForm={setEditForm as any}
        editingTag={editingTag}
        loading={loading}
        onSubmit={handleUpdateTag}
        onCreate={handleCreateTag}
        t={t}
      />
    </div>
  );
}

// Unified Tag Dialog Component for both Create and Edit
interface TagDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  mode: 'create' | 'edit';
  form: CreateTagForm | EditTagForm;
  setForm: React.Dispatch<React.SetStateAction<CreateTagForm | EditTagForm>>;
  editingTag?: TagItem | null;
  loading: boolean;
  onSubmit?: () => Promise<void>;
  onCreate?: () => Promise<void>;
  t: (key: string) => string;
}

function TagDialog({ open, onOpenChange, mode, form, setForm, editingTag, loading, onSubmit, onCreate, t }: TagDialogProps) {
  const handleSubmit = async () => {
    if (mode === 'create') {
      await onCreate?.();
      if (!loading) {
        setForm({
          namespace: '',
          name: '',
          zhText: '',
          zhIntro: '',
          enText: '',
          enIntro: '',
          links: '',
        });
        onOpenChange(false);
      }
    } else {
      await onSubmit?.();
    }
  };

  const handleClose = () => {
    if (!loading) {
      onOpenChange(false);
      if (mode === 'create') {
        setForm({
          namespace: '',
          name: '',
          zhText: '',
          zhIntro: '',
          enText: '',
          enIntro: '',
          links: '',
        });
      }
    }
  };

  const isFormValid = form.namespace && form.name;

  return (
    <>
      {mode === 'create' && (
        <Button
          onClick={() => onOpenChange(true)}
          className="flex items-center gap-2"
        >
          <Plus className="w-4 h-4" />
          {t('settings.createNewTag')}
        </Button>
      )}
      <Dialog open={open} onOpenChange={handleClose}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              {mode === 'create' ? t('settings.createNewTag') : t('settings.tagEditTag')}
            </DialogTitle>
            <DialogDescription>
              {mode === 'create'
                ? t('settings.createNewTagDescription')
                : editingTag
                ? `${editingTag.namespace}:${editingTag.name}`
                : ''}
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-4 max-h-[60vh] overflow-y-auto">
            <div className="grid gap-3 sm:grid-cols-2">
              <div className="space-y-2">
                <Label htmlFor="namespace">{t('settings.tagNamespace')} *</Label>
                <Input
                  id="namespace"
                  value={form.namespace}
                  onChange={(e) => setForm({ ...form, namespace: e.target.value })}
                  placeholder={t('settings.tagNamespacePlaceholder')}
                  disabled={loading}
                  maxLength={64}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="name">{t('settings.tagName')} *</Label>
                <Input
                  id="name"
                  value={form.name}
                  onChange={(e) => setForm({ ...form, name: e.target.value })}
                  placeholder={t('settings.tagNamePlaceholder')}
                  disabled={loading}
                  maxLength={255}
                />
              </div>
            </div>

            <Tabs defaultValue="zh" className="w-full">
              <TabsList>
                <TabsTrigger value="zh">中文</TabsTrigger>
                <TabsTrigger value="en">English</TabsTrigger>
              </TabsList>
              <TabsContent value="zh" className="space-y-3">
                <div className="space-y-2">
                  <Label htmlFor="zhText">{t('settings.tagZhName')}</Label>
                  <Input
                    id="zhText"
                    value={form.zhText}
                    onChange={(e) => setForm({ ...form, zhText: e.target.value })}
                    placeholder={t('settings.tagZhNamePlaceholder')}
                    disabled={loading}
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="zhIntro">{t('settings.tagZhIntro')}</Label>
                  <Textarea
                    id="zhIntro"
                    value={form.zhIntro}
                    onChange={(e) => setForm({ ...form, zhIntro: e.target.value })}
                    placeholder={t('settings.tagZhIntroPlaceholder')}
                    disabled={loading}
                    rows={3}
                  />
                </div>
              </TabsContent>
              <TabsContent value="en" className="space-y-3">
                <div className="space-y-2">
                  <Label htmlFor="enText">{t('settings.tagEnName')}</Label>
                  <Input
                    id="enText"
                    value={form.enText}
                    onChange={(e) => setForm({ ...form, enText: e.target.value })}
                    placeholder={t('settings.tagEnNamePlaceholder')}
                    disabled={loading}
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="enIntro">{t('settings.tagEnIntro')}</Label>
                  <Textarea
                    id="enIntro"
                    value={form.enIntro}
                    onChange={(e) => setForm({ ...form, enIntro: e.target.value })}
                    placeholder={t('settings.tagEnIntroPlaceholder')}
                    disabled={loading}
                    rows={3}
                  />
                </div>
              </TabsContent>
            </Tabs>

            <div className="space-y-2">
              <Label htmlFor="links">{t('settings.tagExternalLinks')}</Label>
              <Input
                id="links"
                value={form.links}
                onChange={(e) => setForm({ ...form, links: e.target.value })}
                placeholder={t('settings.tagExternalLinksPlaceholder')}
                disabled={loading}
              />
            </div>
          </div>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={handleClose}
              disabled={loading}
            >
              {t('common.cancel')}
            </Button>
            <Button
              onClick={handleSubmit}
              disabled={loading || !isFormValid}
            >
              {mode === 'create'
                ? (loading ? t('settings.tagCreating') : t('settings.tagCreate'))
                : (loading ? t('settings.tagSaving') : t('settings.tagSaveChanges'))}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
