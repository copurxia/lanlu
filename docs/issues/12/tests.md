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

## Green verification

```text
corepack pnpm exec vitest run src/lib/source-filter-options.spec.ts
Test Files 1 passed (1), Tests 4 passed (4)

corepack pnpm run test
Test Files 4 passed (4), Tests 23 passed (23)

corepack pnpm run typecheck
passed

corepack pnpm run build
passed (Next.js compiled, TypeScript passed, 22 static pages generated)
```

## Lint note

`eslint src/lib/source-filter-options.ts src/lib/source-filter-options.spec.ts`
passes. Running eslint over the whole existing `source/page.tsx` reports two
pre-existing errors at lines 99 and 110 (`react-hooks/set-state-in-effect`,
`prefer-const`), outside this issue's diff.
