import { describe, expect, it } from 'vitest';

import type { SourceFilter } from './services/source-plugin-service';
import {
  SOURCE_FILTER_ALL_VALUE,
  getDefaultFilterLabel,
  getSelectFilterItems,
  toSelectFilterValue,
  toSourceFilterValue,
} from './source-filter-options';

function filterWith(
  label: string,
  options: Array<{ label: string; value: string }>,
): SourceFilter {
  return { key: 'test', label, type: 'select', options };
}

describe('source filter select options', () => {
  it('uses the plugin empty-option label as the default display label', () => {
    const filter = filterWith('分类', [
      { label: '同人志: 选择', value: '' },
      { label: '同人志', value: 'doujinshi' },
    ]);

    expect(getDefaultFilterLabel(filter)).toBe('同人志: 选择');
  });

  it('falls back to the filter label, then the first option label', () => {
    expect(
      getDefaultFilterLabel(
        filterWith('语言', [
          { label: '中文', value: 'zh' },
          { label: '英文', value: 'en' },
        ]),
      ),
    ).toBe('语言');

    expect(
      getDefaultFilterLabel(
        filterWith('', [
          { label: '中文', value: 'zh' },
          { label: '英文', value: 'en' },
        ]),
      ),
    ).toBe('中文');
  });

  it('keeps the empty option as the single default item and preserves non-empty values', () => {
    const filter = filterWith('分类', [
      { label: '同人志: 选择', value: '' },
      { label: '同人志', value: 'doujinshi' },
      { label: '漫画', value: 'manga' },
    ]);

    expect(getSelectFilterItems(filter)).toEqual([
      { label: '同人志: 选择', value: SOURCE_FILTER_ALL_VALUE },
      { label: '同人志', value: 'doujinshi' },
      { label: '漫画', value: 'manga' },
    ]);
  });

  it('maps empty selections to the sentinel and the sentinel back to an empty request value', () => {
    expect(toSelectFilterValue(undefined)).toBe(SOURCE_FILTER_ALL_VALUE);
    expect(toSelectFilterValue(null)).toBe(SOURCE_FILTER_ALL_VALUE);
    expect(toSelectFilterValue('')).toBe(SOURCE_FILTER_ALL_VALUE);
    expect(toSelectFilterValue('manga')).toBe('manga');

    expect(toSourceFilterValue(SOURCE_FILTER_ALL_VALUE)).toBe('');
    expect(toSourceFilterValue('manga')).toBe('manga');
  });
});
