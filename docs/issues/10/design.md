# Issue #10 design

## Minimal change

Add `apps/web/src/lib/sidebar-navigation.ts` with pure sidebar URL helpers:

- `SMART_FILTER_PARAM_KEYS` lists `newonly`, `untaggedonly`, `date_from` and
  `date_to`.
- `clearSmartFilterParams()` removes those keys from a copied parameter set.
- `buildCategoryHref()` moves the existing category-link construction into a
  testable helper and also clears the smart-filter keys.
- `isCategoryActive()` requires no active smart-filter parameters in addition to
  the existing path/search/category checks.
- `hasActiveSmartFilterParams()` checks for effective `true` booleans or
  non-empty dates.
- `getSmartFilterSidebarState()` returns the existing smart-filter href when
  inactive, or a cancellation href when the current URL exactly matches that
  smart filter.

Update `apps/web/src/components/layout/AppSidebarNav.tsx` to use these helpers for
all category links, both category active checks, smart-filter hrefs and smart
active states. Remove the now-duplicated local helpers.

## Why this approach

- It directly tests the three issue contracts without rendering the full Next.js
  sidebar and its API-driven children.
- The category helper keeps the existing `q`/`page`/relevance cleanup, avoiding a
  behavioral regression unrelated to smart filters.
- Cancellation is computed from the current URL rather than a hard-coded `/`, so
  folder, sorting and grouping selections survive the toggle.

## Alternatives considered

- Inline conditional logic in `AppSidebarNav.tsx`: smaller diff but not testable
  without a complicated component/API mock.
- Clear every query parameter on cancel: too broad; it would discard folder/sort
  state that the issue asks to preserve.
- Change `buildSmartFilterHref()` itself: unnecessary and would affect other
  consumers; the toggle is a sidebar navigation concern.

## Files

- `apps/web/src/lib/sidebar-navigation.ts` (new)
- `apps/web/src/lib/sidebar-navigation.spec.ts` (new)
- `apps/web/src/components/layout/AppSidebarNav.tsx`
- `docs/issues/10/{requirements,design,tests,review}.md`

## Rollback

Revert the single issue commit. No persisted data, API or schema changes are
involved.
