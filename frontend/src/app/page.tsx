'use client';

import { SearchBar } from '@/components/search/SearchBar';
import { ArchiveGrid } from '@/components/archive/ArchiveGrid';
import { Pagination } from '@/components/ui/pagination';
import { Spinner } from '@/components/ui/spinner';
import { ArchiveService } from '@/lib/archive-service';
import { Button } from '@/components/ui/button';
import { Shuffle } from 'lucide-react';
import Link from 'next/link';
import { useState, useEffect, useCallback } from 'react';

export default function HomePage() {
  const [archives, setArchives] = useState<any[]>([]);
  const [randomArchives, setRandomArchives] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [randomLoading, setRandomLoading] = useState(true);
  const [currentPage, setCurrentPage] = useState(0);
  const [totalPages, setTotalPages] = useState(0);
  const [totalRecords, setTotalRecords] = useState(0);
  const pageSize = 20;

  const fetchArchives = useCallback(async (page: number = 0) => {
    try {
      setLoading(true);
      const result = await ArchiveService.search({
        start: page * pageSize,
        count: pageSize,
        sortby: 'lastreadtime',
        order: 'desc'
      });
      
      setArchives(result.data);
      setTotalRecords(result.recordsTotal);
      setTotalPages(Math.ceil(result.recordsTotal / pageSize));
    } catch (error) {
      console.error('Failed to fetch archives:', error);
      setArchives([]);
    } finally {
      setLoading(false);
    }
  }, [pageSize]);

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
    fetchArchives(currentPage);
    fetchRandomArchives();
  }, [currentPage, fetchArchives, fetchRandomArchives]);

  const handlePageChange = (page: number) => {
    setCurrentPage(page);
  };
  
  return (
    <div className="container mx-auto px-4 py-8">
      {/* 搜索区域 */}
      <section className="text-center mb-12">
        <h1 className="text-4xl font-bold mb-4">Lanraragi4CJ</h1>
        <p className="text-muted-foreground mb-8">漫画归档管理系统</p>
        <div className="flex justify-center mb-4">
          <SearchBar />
        </div>
        <Button asChild variant="outline">
          <Link href="/search">
            <Shuffle className="w-4 h-4 mr-2" />
            高级搜索
          </Link>
        </Button>
      </section>
      
      {/* 随机推荐 */}
      <section className="mb-16">
        <h2 className="text-2xl font-semibold mb-6">随机推荐</h2>
        {randomLoading ? (
          <div className="text-center py-12">
            <Spinner size="lg" />
            <p className="text-muted-foreground mt-4">加载中...</p>
          </div>
        ) : randomArchives.length > 0 ? (
          <ArchiveGrid archives={randomArchives} />
        ) : (
          <div className="text-center py-12">
            <p className="text-muted-foreground">暂无推荐档案</p>
          </div>
        )}
      </section>
      
      {/* 档案列表 */}
      <section>
        <div className="flex items-center justify-between mb-6">
          <h2 className="text-2xl font-semibold">所有档案</h2>
          <div className="text-sm text-muted-foreground">
            共 {totalRecords} 个档案，第 {currentPage + 1} 页，共 {totalPages} 页
          </div>
        </div>
        
        {loading ? (
          <div className="text-center py-12">
            <Spinner size="lg" />
            <p className="text-muted-foreground mt-4">加载中...</p>
          </div>
        ) : archives.length > 0 ? (
          <>
            <ArchiveGrid archives={archives} />
            
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
            <p className="text-muted-foreground">暂无档案</p>
          </div>
        )}
      </section>
    </div>
  );
}