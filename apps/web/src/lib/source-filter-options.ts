import type { SourceFilter, SourceFilterOption } from './services/source-plugin-service';

// Internal display sentinel for "no filter". A plugin option whose real value is
// also "_all" would collide with it; keep this out of plugin schema contracts.
export const SOURCE_FILTER_ALL_VALUE = '_all';

function nonEmptyLabel(label: string | undefined): string | undefined {
  return label?.trim() ? label : undefined;
}

export function getDefaultFilterLabel(
  filter: Pick<SourceFilter, 'label' | 'options'>,
): string {
  const emptyOption = filter.options?.find((option) => option.value === '');
  return (
    nonEmptyLabel(emptyOption?.label)
    ?? nonEmptyLabel(filter.label)
    ?? nonEmptyLabel(filter.options?.[0]?.label)
    ?? ''
  );
}

export function getSelectFilterItems(
  filter: Pick<SourceFilter, 'label' | 'options'>,
): SourceFilterOption[] {
  return [
    { label: getDefaultFilterLabel(filter), value: SOURCE_FILTER_ALL_VALUE },
    ...(filter.options ?? []).filter((option) => option.value !== ''),
  ];
}

export function toSelectFilterValue(value: unknown): string {
  return value === '' || value == null ? SOURCE_FILTER_ALL_VALUE : String(value);
}

export function toSourceFilterValue(selectValue: string): string {
  return selectValue === SOURCE_FILTER_ALL_VALUE ? '' : selectValue;
}
