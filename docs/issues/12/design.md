# Issue #12 design

## Minimal change

Add `apps/web/src/lib/source-filter-options.ts` as a small pure helper module:

- `toSelectFilterValue(value)` maps empty/null values to the existing `_all`
  sentinel.
- `toSourceFilterValue(selectValue)` maps `_all` back to `""` and preserves all
  non-empty values.
- `getDefaultFilterLabel(filter)` chooses the explicit empty-option label,
  then `filter.label`, then the first option label.
- `getSelectFilterItems(filter)` returns the `_all` item followed by all
  non-empty plugin options exactly once.

Update the `select` branch in
`apps/web/src/app/(header)/source/page.tsx` to use these helpers for the
controlled value, change handler and menu items. The empty option remains the
default request value (`""`) but its label is no longer discarded.

## Why this approach

- The helpers isolate display/transport mapping and make the acceptance
  criteria directly testable without rendering the full Next.js page.
- The internal URL/request state stays unchanged, so existing query behavior
  and pagination are preserved.
- It avoids a broader refactor of all filter types and does not touch the
  plugin service, which already retains `value: ""` options.

## Alternatives considered

- Inline the logic in `page.tsx`: smaller diff, but hard to regression-test and
  easy to rebreak.
- Change `SourcePluginService.getFilters()`: unnecessary because it already
  returns empty options; changing it would not fix the display layer.
- Select the first non-empty option by default: rejected because it changes the
  request semantics and does not represent “no filter”.

## Files

- `apps/web/src/lib/source-filter-options.ts` (new)
- `apps/web/src/lib/source-filter-options.spec.ts` (new)
- `apps/web/src/components/source/SourceSelectFilter.tsx`
- `apps/web/src/components/source/SourceSelectFilter.test.tsx`
- `apps/web/src/app/(header)/source/page.tsx`
- `docs/issues/12/{requirements,design,tests,review}.md`

## Rollback

Revert the single issue commit. No database, API, schema or persisted-data
changes are involved.
