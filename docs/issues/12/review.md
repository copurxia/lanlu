# Issue #12 review

## Diff scope

- `apps/web/src/lib/source-filter-options.ts` (new pure helper module)
- `apps/web/src/lib/source-filter-options.spec.ts` (new tests)
- `apps/web/src/app/(header)/source/page.tsx` (select branch only)
- `docs/issues/12/*`

No backend, plugin service, database, URL parameter names or other filter
types were changed.

## Self-review

- Request semantics: `_all` is still converted to `""` before it enters
  `filterValues`; non-empty option values pass through unchanged. No default
  first-option value is selected.
- Display semantics: the plugin-provided empty-option label is preferred, then
  `filter.label`, then the first option label. The hard-coded `全部` item is
  removed from `select` filters.
- Data handling: empty options are no longer dropped; they become the single
  `_all` menu item, so there is no duplicate empty entry.
- Compatibility: `tabs`, `multi-select`, `toggle`, `text` and `range` branches
  are untouched.
- Security/performance: pure string mapping, no new network calls, storage or
  user-controlled HTML.

## Verification

- Full Vitest suite: 4 files, 23 tests passed.
- `tsc --noEmit`: passed.
- `next build` + brotli generation: passed.
- New files pass eslint.

## Assumptions and residual risks

- The issue uses the pre-migration `frontend/...` paths; this fix targets the
  current `apps/web/...` equivalents.
- The internal `_all` sentinel remains unchanged for backward compatibility. A
  hypothetical plugin option literally named `_all` would collide with it, but
  no such option exists in the current schema and changing the sentinel would
  be outside this issue.
- Whole-page eslint still reports two pre-existing errors in untouched code at
  `source/page.tsx:99` and `:110`; they are recorded rather than fixed here to
  keep the change scoped.
