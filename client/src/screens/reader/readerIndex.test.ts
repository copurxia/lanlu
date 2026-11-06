import { readerItemIndexForPage, webtoonIndexForPage } from './readerIndex';

const items = [
  { progressPage: 1, pages: [{ pageNumber: 1 }] },
  { progressPage: 2, pages: [{ pageNumber: 2 }, { pageNumber: 3 }] },
  { progressPage: 4, pages: [{ pageNumber: 4 }] },
];

describe('readerIndex', () => {
  it('finds an item by its progress page', () => {
    expect(readerItemIndexForPage(items, 2)).toBe(1);
    expect(readerItemIndexForPage(items, 4)).toBe(2);
  });

  it('finds an item by a member page in a spread', () => {
    expect(readerItemIndexForPage(items, 3)).toBe(1);
  });

  it('falls back to zero for missing pages and empty lists', () => {
    expect(readerItemIndexForPage(items, 99)).toBe(0);
    expect(readerItemIndexForPage([], 1)).toBe(0);
  });

  it('maps a webtoon page to a clamped item index', () => {
    expect(webtoonIndexForPage(1, 10)).toBe(0);
    expect(webtoonIndexForPage(5, 10)).toBe(4);
    expect(webtoonIndexForPage(50, 10)).toBe(9);
    expect(webtoonIndexForPage(3, 0)).toBe(0);
  });
});
