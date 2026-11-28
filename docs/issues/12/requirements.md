# Issue #12 requirements

Issue: https://git.copur.xyz/copur/lanlu/issues/12
Title: 在线源筛选下拉框全部显示“全部”，空字符串选项丢失插件配置的显示名

## Problem

The online-source filter bar maps every empty/null selected value to the internal
sentinel `_all` and renders a hard-coded `全部` item. It also drops plugin options
whose value is `""`. As a result, all collapsed `select` filters show the same
text and users cannot distinguish status, language, rating, length and category
filters.

The issue predates the repository migration; the current implementation lives in
`apps/web` (the old issue path `frontend/...` maps to `apps/web/...`).

## Acceptance criteria

1. For a `select` filter, the default item's display label is the label of the
   plugin-provided option with `value === ""` when that label is non-empty.
2. If no explicit empty option label exists, the default item falls back to
   `filter.label`, then to the first option label.
3. The internal `_all` value continues to map to `""` in `filterValues`, so the
   request/query semantics of “no filter” are unchanged.
4. Selecting a non-empty plugin option keeps that option's exact value; default
   display must never enable the first non-empty option.
5. The dropdown menu shows the plugin's empty-option label instead of a
   hard-coded `全部`; there is no duplicate empty option.
6. Existing `tabs`, `multi-select`, `toggle`, `text` and `range` behavior is not
   changed.

## Boundaries

- Frontend rendering only; the plugin service already preserves empty-valued
  options and is not changed.
- Backend SQL/API behavior and URL parameter names are unchanged.
- No localization or schema changes are introduced.

## Assumptions

- A plugin empty option is represented exactly by `value: ""`.
- Filter labels are non-empty because `SourcePluginService.getFilters()` rejects
  filters without a label.
- The intended fix is limited to `select` filters, matching the issue's
  “下拉框” scope.
