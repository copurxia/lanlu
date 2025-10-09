'use client';

import { useSearchParams } from 'next/navigation';
import { useState, useEffect, Suspense } from 'react';
import { ArchiveService } from '@/lib/archive-service';
import { ArchiveMetadata } from '@/types/archive';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { ArrowLeft, BookOpen, Download, Tag, Calendar, FileText } from 'lucide-react';
import Link from 'next/link';

function ArchiveDetailContent() {
  const searchParams = useSearchParams();
  const id = searchParams.get('id');
  
  const [metadata, setMetadata] = useState<ArchiveMetadata | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    async function fetchMetadata() {
      if (!id) {
        setError('缺少归档ID参数');
        setLoading(false);
        return;
      }

      try {
        const data = await ArchiveService.getMetadata(id);
        setMetadata(data);
      } catch (err) {
        console.error('Failed to fetch archive metadata:', err);
        setError('获取归档信息失败');
      } finally {
        setLoading(false);
      }
    }

    fetchMetadata();
  }, [id]);

  if (loading) {
    return (
      <div className="container mx-auto px-4 py-8">
        <div className="text-center py-12">
          <p className="text-muted-foreground">加载中...</p>
        </div>
      </div>
    );
  }

  if (error || !metadata) {
    return (
      <div className="container mx-auto px-4 py-8">
        <div className="text-center py-12">
          <p className="text-red-500 mb-4">{error || '归档不存在'}</p>
          <Link href="/">
            <Button variant="outline">
              <ArrowLeft className="w-4 h-4 mr-2" />
              返回首页
            </Button>
          </Link>
        </div>
      </div>
    );
  }

  const tags = metadata.tags ? metadata.tags.split(',').map(tag => tag.trim()).filter(tag => tag) : [];

  return (
    <div className="container mx-auto px-4 py-8">
      {/* 返回按钮 */}
      <div className="mb-6">
        <Link href="/">
          <Button variant="outline">
            <ArrowLeft className="w-4 h-4 mr-2" />
            返回首页
          </Button>
        </Link>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        {/* 左侧：缩略图 */}
        <div className="lg:col-span-1">
          <Card>
            <CardContent className="p-4">
              <div className="aspect-[3/4] bg-muted relative">
                <img
                  src={ArchiveService.getThumbnailUrl(metadata.arcid)}
                  alt={metadata.title}
                  className="w-full h-full object-cover rounded-md"
                />
              </div>
            </CardContent>
          </Card>

          {/* 操作按钮 */}
          <div className="mt-4 space-y-2">
            <Link href={`/reader?id=${metadata.arcid}`}>
              <Button className="w-full">
                <BookOpen className="w-4 h-4 mr-2" />
                开始阅读
              </Button>
            </Link>
            <Button
              variant="outline"
              className="w-full"
              onClick={() => {
                if (metadata) {
                  const downloadUrl = ArchiveService.getDownloadUrl(metadata.arcid);
                  window.open(downloadUrl, '_blank');
                }
              }}
            >
              <Download className="w-4 h-4 mr-2" />
              下载归档
            </Button>
          </div>
        </div>

        {/* 右侧：详细信息 */}
        <div className="lg:col-span-2 space-y-6">
          {/* 标题和基本信息 */}
          <Card>
            <CardHeader>
              <CardTitle className="text-2xl">{metadata.title}</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div className="flex items-center space-x-2">
                  <Calendar className="w-4 h-4 text-muted-foreground" />
                  <span className="text-sm text-muted-foreground">最后阅读:</span>
                  <span className="text-sm">{metadata.lastreadtime ? new Date(metadata.lastreadtime * 1000).toLocaleDateString() : '未阅读'}</span>
                </div>
                <div className="flex items-center space-x-2">
                  <BookOpen className="w-4 h-4 text-muted-foreground" />
                  <span className="text-sm text-muted-foreground">页数:</span>
                  <span className="text-sm">{metadata.pagecount}</span>
                </div>
                <div className="flex items-center space-x-2">
                  <BookOpen className="w-4 h-4 text-muted-foreground" />
                  <span className="text-sm text-muted-foreground">进度:</span>
                  <span className="text-sm">{metadata.progress}/{metadata.pagecount}</span>
                </div>
                <div className="flex items-center space-x-2">
                  <Tag className="w-4 h-4 text-muted-foreground" />
                  <span className="text-sm text-muted-foreground">状态:</span>
                  <span className="text-sm">{metadata.isnew === 'true' ? '新归档' : '已阅读'}</span>
                </div>
              </div>
            </CardContent>
          </Card>

          {/* 标签 */}
          {tags.length > 0 && (
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center">
                  <Tag className="w-4 h-4 mr-2" />
                  标签
                </CardTitle>
              </CardHeader>
              <CardContent>
                <div className="flex flex-wrap gap-2">
                  {tags.map((tag, index) => (
                    <Badge key={index} variant="secondary">
                      {tag}
                    </Badge>
                  ))}
                </div>
              </CardContent>
            </Card>
          )}
        </div>
      </div>
    </div>
  );
}

export default function ArchiveDetailPage() {
  return (
    <Suspense fallback={
      <div className="container mx-auto px-4 py-8">
        <div className="text-center py-12">
          <p className="text-muted-foreground">加载中...</p>
        </div>
      </div>
    }>
      <ArchiveDetailContent />
    </Suspense>
  );
}