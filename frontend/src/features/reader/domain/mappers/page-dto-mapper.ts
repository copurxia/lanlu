import type { PageInfo } from "@/lib/services/archive-service";
import type { ReaderPageItem } from "@/features/reader/domain/models/reader-item";

export function mapPageDtoToReaderPageItem(page: PageInfo, archiveId: string): ReaderPageItem {
  return {
    ...page,
    archiveId,
  };
}

export function mapPageDtosToReaderPageItems(pages: PageInfo[], archiveId: string): ReaderPageItem[] {
  return pages.map((page) => mapPageDtoToReaderPageItem(page, archiveId));
}
