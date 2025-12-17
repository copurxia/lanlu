'use client';

import { ArchiveGrid } from '@/components/archive/ArchiveGrid';
import { HomeArchiveCard } from '@/components/archive/HomeArchiveCard';
import { Pagination } from '@/components/ui/pagination';
import { Spinner } from '@/components/ui/spinner';
import { Button } from '@/components/ui/button';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Header } from '@/components/layout/Header';
import { SearchSidebar } from '@/components/layout/SearchSidebar';
import { ArchiveService } from '@/lib/archive-service';
import { appEvents, AppEvents } from '@/lib/events';
import { RefreshCw } from 'lucide-react';
import { useState, useEffect, useCallback } from 'react';
import { useLanguage } from '@/contexts/LanguageContext';

export default function HomePage() {
  const { t } = useLanguage();
  
  const [archives, setArchives] = useState<any[]>([]);
  const [randomArchives, setRandomArchives] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [randomLoading, setRandomLoading] = useState(true);
  const [currentPage, setCurrentPage] = useState(0);
  const [totalPages, setTotalPages] = useState(0);
  const [totalRecords, setTotalRecords] = useState(0);
  const [sortBy, setSortBy] = useState('date_added');
  const [sortOrder, setSortOrder] = useState('desc');
  const [searchQuery, setSearchQuery] = useState('');
  const [searchTags, setSearchTags] = useState<string[]>([]);
  const [searchCategory, setSearchCategory] = useState('');
  const [newonly, setNewonly] = useState(false);
  const [untaggedonly, setUntaggedonly] = useState(false);
  const pageSize = 20;

  const fetchArchives = useCallback(async (page: number = 0) => {
    try {
      setLoading(true);
      const params: any = {
        start: page * pageSize,
        count: pageSize,
        sortby: sortBy,
        order: sortOrder
      };

      if (searchQuery) params.filter = searchQuery;
      if (searchTags.length > 0) params.tag = searchTags.join(',');
      if (searchCategory) params.category = searchCategory;
      if (newonly) params.newonly = true;
      if (untaggedonly) params.untaggedonly = true;

      const result = await ArchiveService.search(params);

      setArchives(result.data);
      setTotalRecords(result.recordsTotal);
      setTotalPages(Math.ceil(result.recordsTotal / pageSize));
    } catch (error) {
      console.error('Failed to fetch archives:', error);
      setArchives([]);
    } finally {
      setLoading(false);
    }
  }, [pageSize, sortBy, sortOrder, searchQuery, searchTags, searchCategory, newonly, untaggedonly]);

  const fetchRandomArchives = useCallback(async () => {
    try {
      setRandomLoading(true);
      const archives = await ArchiveService.getRandom({ count: 8 });
      setRandomArchives(archives);
    } catch (error) {
      console.error('Failed to fetch random archives:', error);
      setRandomArchives([]);
    } finally {
      setRandomLoading(false);
    }
  }, []);

  useEffect(() => {
    // 只在客户端执行数据获取，避免静态生成时的API调用
    if (typeof window !== 'undefined') {
      fetchArchives(currentPage);
      fetchRandomArchives();
    }
  }, [currentPage, fetchArchives, fetchRandomArchives, sortBy, sortOrder, newonly, untaggedonly]);

  // 监听上传完成事件，刷新首页数据
  useEffect(() => {
    const handleUploadCompleted = () => {
      console.log('Upload completed, refreshing homepage data');
      fetchArchives(currentPage);
      fetchRandomArchives();
    };

    const handleArchivesRefresh = () => {
      console.log('Archives refresh event received');
      fetchArchives(currentPage);
      fetchRandomArchives();
    };

    appEvents.on(AppEvents.UPLOAD_COMPLETED, handleUploadCompleted);
    appEvents.on(AppEvents.ARCHIVES_REFRESH, handleArchivesRefresh);

    return () => {
      appEvents.off(AppEvents.UPLOAD_COMPLETED, handleUploadCompleted);
      appEvents.off(AppEvents.ARCHIVES_REFRESH, handleArchivesRefresh);
    };
  }, [currentPage, fetchArchives, fetchRandomArchives]);

  const handleSearch = (params: {
    query?: string;
    tags?: string[];
    category?: string;
    sortBy?: string;
    sortOrder?: string;
    dateFrom?: string;
    dateTo?: string;
    newonly?: boolean;
    untaggedonly?: boolean;
  }) => {
    setSearchQuery(params.query || '');
    setSearchTags(params.tags || []);
    setSearchCategory(params.category || '');
    if (params.sortBy) setSortBy(params.sortBy);
    if (params.sortOrder) setSortOrder(params.sortOrder);
    if (typeof params.newonly === 'boolean') setNewonly(params.newonly);
    if (typeof params.untaggedonly === 'boolean') setUntaggedonly(params.untaggedonly);
    setCurrentPage(0);
  };

  const handlePageChange = (page: number) => {
    setCurrentPage(page);
  };
  
  
  return (
    <div className="min-h-screen bg-background">
      <Header />

      <div className="flex min-h-screen">
        {/* 侧栏 - 桌面端显示 */}
        <div className="hidden lg:block flex-shrink-0 border-r border-border">
          <SearchSidebar onSearch={handleSearch} loading={loading} />
        </div>
        
        {/* 主内容区 */}
        <main className="flex-1 min-w-0 px-4 py-8">
          {/* 随机推荐 */}
          <section className="mb-12">
            <div className="flex items-center justify-between mb-6">
              <h2 className="text-2xl font-semibold">{t('home.randomRecommendations')}</h2>
              <div className="flex items-center gap-2">
                <Button
                  variant="outline"
                  size="sm"
                  onClick={fetchRandomArchives}
                  disabled={randomLoading}
                  className="border-border bg-background hover:bg-accent hover:text-accent-foreground"
                >
                  <RefreshCw className={`w-4 h-4 mr-2 ${randomLoading ? 'animate-spin' : ''}`} />
                  {t('common.refresh')}
                </Button>
              </div>
            </div>
            
            {randomLoading ? (
              <div className="text-center py-12">
                <Spinner size="lg" />
                <p className="text-muted-foreground mt-4">{t('common.loading')}</p>
              </div>
            ) : randomArchives.length > 0 ? (
              <div className="overflow-x-auto pb-4">
                <div className="flex gap-4 min-w-max">
                  {randomArchives.map((archive) => (
                    <HomeArchiveCard key={archive.arcid} archive={archive} />
                  ))}
                </div>
              </div>
            ) : (
              <div className="text-center py-12">
                <p className="text-muted-foreground">{t('home.noRecommendations')}</p>
              </div>
            )}
          </section>
          
          {/* 档案列表 */}
          <section>
            <div className="flex flex-col gap-4 mb-6">
              {/* PC端：标题、档案数量和排序控件在一行；移动端：分行显示 */}
              <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
                <h2 className="text-2xl font-semibold">
                  {searchQuery || searchTags.length > 0 || searchCategory ? t('home.searchResults') : t('home.allArchives')}
                </h2>
                
                <div className="flex flex-col sm:flex-row sm:items-center gap-4">
                  <div className="text-sm text-muted-foreground">
                    {t('home.archivesCount').replace('{count}', String(totalRecords)).replace('{page}', String(currentPage + 1)).replace('{totalPages}', String(totalPages))}
                  </div>
                  
                  <div className="flex items-center gap-2">
                    <span className="text-sm text-muted-foreground">{t('home.sortBy')}</span>
                    <Select value={sortBy} onValueChange={setSortBy}>
                      <SelectTrigger className="w-[140px] h-8">
                        <SelectValue>
                          {sortBy === 'lastreadtime' && t('home.lastRead')}
                          {sortBy === 'date_added' && t('home.dateAdded')}
                          {sortBy === 'pagecount' && t('home.pageCount')}
                        </SelectValue>
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="lastreadtime">{t('home.lastRead')}</SelectItem>
                        <SelectItem value="date_added">{t('home.dateAdded')}</SelectItem>
                        <SelectItem value="pagecount">{t('home.pageCount')}</SelectItem>
                      </SelectContent>
                    </Select>
                    
                    <Select value={sortOrder} onValueChange={setSortOrder}>
                      <SelectTrigger className="w-[100px] h-8">
                        <SelectValue>
                          {sortOrder === 'asc' && t('common.asc')}
                          {sortOrder === 'desc' && t('common.desc')}
                        </SelectValue>
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="asc">{t('common.asc')}</SelectItem>
                        <SelectItem value="desc">{t('common.desc')}</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>
                </div>
              </div>
            </div>
            
            {loading ? (
              <div className="text-center py-12">
                <Spinner size="lg" />
                <p className="text-muted-foreground mt-4">{t('common.loading')}</p>
              </div>
            ) : archives.length > 0 ? (
              <>
                <ArchiveGrid archives={archives} variant="home" />
                
                {totalPages > 1 && (
                  <div className="mt-8">
                    <Pagination
                      currentPage={currentPage}
                      totalPages={totalPages}
                      onPageChange={handlePageChange}
                    />
                  </div>
                )}
              </>
            ) : (
              <div className="text-center py-12">
                <p className="text-muted-foreground">
                  {searchQuery || searchTags.length > 0 || searchCategory ? t('home.noMatchingArchives') : t('home.noArchives')}
                </p>
              </div>
            )}
          </section>
        </main>
      </div>
    </div>
  );
}
