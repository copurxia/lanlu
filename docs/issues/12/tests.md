# Issue #12 test evidence

## Baseline before changes

Run in `apps/web`:

```text
corepack pnpm run test        -> 3 test files, 19 tests passed
corepack pnpm run typecheck   -> passed
```

## Red test

Added `apps/web/src/lib/source-filter-options.spec.ts` before the helper module
existed. The targeted run failed as expected:

```text
corepack pnpm exec vitest run src/lib/source-filter-options.spec.ts
Error: Failed to resolve import "./source-filter-options" ...
Test Files 1 failed (1)
```

Coverage:

- explicit empty-option label wins for the default item;
- fallback to `filter.label`, then the first option label;
- the empty option is represented once as the `_all` item, and non-empty
  options keep their exact values;
- `undefined`, `null` and `""` map to `_all`, and `_all` maps back to `""`;
- a non-empty selected value is preserved.

## Review follow-up: component wiring test

Added `SourceSelectFilter` as the component used by the source page and a Radix
Select rendering test. The test first verifies that the collapsed trigger shows
`同人志: 选择` while the selected request value is `""`; it then selects that same
plugin empty option from an open menu and verifies that the component emits `""`.
This covers the page-facing wiring rather than only the helper functions.

## Green verification

```text
corepack pnpm exec vitest run src/lib/source-filter-options.spec.ts
Test Files 1 passed (1), Tests 4 passed (4)

corepack pnpm exec vitest run src/components/source/SourceSelectFilter.test.tsx
Test Files 1 passed (1), Tests 1 passed (1)

corepack pnpm run test
Test Files 5 passed (5), Tests 24 passed (24)

corepack pnpm run typecheck
passed

corepack pnpm run build
passed (Next.js compiled, TypeScript passed, 22 static pages generated)
```

## Lint note

`eslint src/lib/source-filter-options.ts src/lib/source-filter-options.spec.ts
src/components/source/SourceSelectFilter.tsx
src/components/source/SourceSelectFilter.test.tsx` passes. Running eslint over
the whole existing `source/page.tsx` reports two pre-existing errors at lines 99
and 110 (`react-hooks/set-state-in-effect`, `prefer-const`), outside this
issue's behavior diff.
