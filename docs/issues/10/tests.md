# Issue #10 test evidence

## Baseline before changes

Run in `apps/web`:

```text
corepack pnpm install --frozen-lockfile -> passed
corepack pnpm run test                  -> 3 files, 19 tests passed
corepack pnpm run typecheck             -> passed
```

## Red test

Added `apps/web/src/lib/sidebar-navigation.spec.ts` before the helper module
existed. The targeted run failed as expected:

```text
corepack pnpm exec vitest run src/lib/sidebar-navigation.spec.ts
Error: Failed to resolve import "./sidebar-navigation" ...
Test Files 1 failed (1)
```

Coverage:

- folder and “全部” URLs clear `newonly`, `untaggedonly`, `date_from` and
  `date_to`, while retaining existing `q`/`page`/relevance cleanup and setting
  `category_id` correctly;
- category active state is false for both “全部” and a folder whenever an
  effective smart-filter parameter remains;
- an active smart filter becomes a cancellation URL that removes the four smart
  parameters and preserves `category_id` and grouping;
- an inactive smart filter still uses `buildSmartFilterHref()`.

## Green verification

```text
corepack pnpm exec vitest run src/lib/sidebar-navigation.spec.ts
Test Files 1 passed (1), Tests 3 passed (3)

corepack pnpm run test
Test Files 4 passed (4), Tests 22 passed (22)

corepack pnpm run typecheck
passed

corepack pnpm run build
passed (Next.js compiled, TypeScript passed, 22 static pages generated)
```

## Lint note

`eslint src/lib/sidebar-navigation.ts src/lib/sidebar-navigation.spec.ts
src/components/layout/AppSidebarNav.tsx` passes.
