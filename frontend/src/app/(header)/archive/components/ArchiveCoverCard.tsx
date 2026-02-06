'use client';

import { useState } from 'react';
import Image from 'next/image';
import { X } from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';

type Props = {
  title: string;
  coverAssetId?: number;
  noCoverLabel: string;
};

export function ArchiveCoverCard({ title, coverAssetId, noCoverLabel }: Props) {
  const [imageModalOpen, setImageModalOpen] = useState(false);
  const [coverError, setCoverError] = useState(false);
  const coverSrc = coverAssetId && coverAssetId > 0 ? `/api/assets/${coverAssetId}` : '';

  return (
    <Card>
      <CardContent className="p-4 lg:p-6">
        <div className="aspect-[3/4] bg-muted relative max-w-[280px] sm:max-w-[360px] lg:max-w-none mx-auto lg:mx-0 group">
          <div className="relative w-full h-full">
            {!coverError && coverSrc.length > 0 && (
              <Image
                src={coverSrc}
                alt={title}
                fill
                className="object-cover rounded-md cursor-pointer transition-all duration-300 hover:scale-105 hover:shadow-xl active:scale-95"
                onClick={() => setImageModalOpen(true)}
                onError={() => setCoverError(true)}
              />
            )}
          </div>

          <div
            className={`absolute inset-0 bg-muted rounded-md items-center justify-center ${coverError ? 'flex' : 'hidden'}`}
          >
            <div className="text-center text-muted-foreground">
              <div className="text-3xl mb-2">📚</div>
              <div className="text-sm">{noCoverLabel}</div>
            </div>
          </div>

          {!coverError && coverSrc.length > 0 && (
            <div className="absolute inset-0 bg-black bg-opacity-0 group-hover:bg-opacity-10 transition-all duration-300 rounded-md flex items-center justify-center pointer-events-none">
              <div className="opacity-0 group-hover:opacity-100 transition-opacity duration-300 bg-white bg-opacity-90 text-gray-800 px-3 py-1 rounded-full text-sm font-medium">
                点击查看大图
              </div>
            </div>
          )}
        </div>

        {imageModalOpen && !coverError && coverSrc.length > 0 && (
          <div
            className="fixed inset-0 bg-black bg-opacity-75 z-[9999] flex items-center justify-center p-4"
            onClick={() => setImageModalOpen(false)}
          >
            <div className="relative max-w-4xl max-h-full">
              <Image
                src={coverSrc}
                alt={title}
                width={800}
                height={1066}
                className="max-w-full max-h-[90vh] w-auto h-auto object-contain rounded-lg"
                onError={() => setCoverError(true)}
                unoptimized
              />
              <button
                className="absolute top-2 right-2 bg-white bg-opacity-20 hover:bg-opacity-30 text-white rounded-full p-2"
                onClick={() => setImageModalOpen(false)}
              >
                <X className="w-6 h-6" />
              </button>
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
