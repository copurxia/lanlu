# Issue #10 requirements

Issue: https://git.copur.xyz/copur/lanlu/issues/10
Title: 智能分类筛选无法取消：切回文件夹分类后残留不可见选中态，导致无法显示全部画廊

## Problem

The Web sidebar constructs folder/category links without clearing the smart-filter
query parameters. Clicking “全部” or a folder after selecting a smart filter keeps
`newonly`, `untaggedonly`, `date_from` and `date_to` active while the folder item
appears selected. Smart-filter links also have no toggle-off path.

The issue predates the repository migration; the current implementation is in
`apps/web` (the old `frontend/` path maps to `apps/web/`).

## Acceptance criteria

1. Clicking “全部” or a folder category removes `newonly`, `untaggedonly`,
   `date_from` and `date_to` from the destination URL.
2. Existing category-navigation behavior remains: `q` and `page` are removed,
   relevance sorting falls back to the default, and the requested `category_id`
   is set (or removed for “全部”).
3. “全部” is visually active only when on `/`, without `q`, with the active
   category equal to `all`, and with no active smart-filter parameters.
4. Folder category items use the same smart-filter exclusion, so a folder never
   appears selected while an invisible smart filter is still active.
5. Clicking an already-active smart-filter item navigates to a cancellation URL
   with the four smart-filter parameters removed; non-smart parameters such as
   folder, sort and grouping are preserved.
6. Clicking an inactive smart-filter item keeps using the existing
   `buildSmartFilterHref()` destination.

## Boundaries

- Web sidebar/navigation only; no backend or smart-filter schema changes.
- Only the four smart-filter parameters named by the issue are cleared.
- `favoriteonly` and unrelated filters are not changed.
- The smart-filter link definition and ordering are unchanged.

## Assumptions

- The current repository path is `apps/web`; issue references to `frontend/` are
  historical.
- Smart-filter boolean parameters are written as `true`, and date parameters are
  non-empty date strings.
- A smart filter that embeds its own `q` is out of scope; cancellation preserves
  `q` exactly like other non-smart parameters, as requested by the current
  contract.
