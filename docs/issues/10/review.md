# Issue #10 review

## Diff scope

- `apps/web/src/lib/sidebar-navigation.ts` (new pure URL/state helpers)
- `apps/web/src/lib/sidebar-navigation.spec.ts` (new tests)
- `apps/web/src/components/layout/AppSidebarNav.tsx`
- `docs/issues/10/*`

No backend, smart-filter schema, source-page or unrelated filter changes.

## Self-review

- Category links now clear the four smart-filter parameters before applying the
  requested folder. Existing `q`/`page` removal and relevance-sort fallback are
  preserved.
- “全部” and folder active states both require no effective smart-filter
  parameters, so an invisible smart filter can no longer produce a false folder
  selection.
- Active smart-filter links now point to a cancellation URL. Cancellation
  removes the four smart keys, drops pagination and preserves folder, query,
  sorting and grouping parameters.
- Inactive smart-filter links still use the unchanged
  `buildSmartFilterHref()` destination.
- Active comparison ignores `category_id` only, allowing an active smart filter
  to be toggled off while returning to the underlying folder. `page` is ignored
  through the existing normalizer.
- Security/performance: pure `URLSearchParams` operations, no network, storage,
  HTML injection or new dependencies.

## Verification

- Full Vitest suite: 4 files, 22 tests passed.
- `tsc --noEmit`: passed.
- `next build` + brotli generation: passed.
- Changed files pass eslint.

## Assumptions and residual risks

- The issue references the old `frontend/` path; this fix targets `apps/web/`.
- Only `newonly`, `untaggedonly`, `date_from` and `date_to` are treated as smart
  parameters. `favoriteonly` and other filters are deliberately untouched.
- Cancellation preserves `q` even if a smart-filter definition itself supplied
  that query. Current smart filters do not do so; changing that would require
  distinguishing filter-owned query text from user search text.
- No browser-level click test was added; the three navigation contracts are
  covered by pure helpers, and the component is wired directly to them.
